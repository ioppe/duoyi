import 'package:flutter/material.dart';
import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'package:provider/provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/notification_service.dart';
import '../models/countdown.dart';
import '../models/goal.dart' show ReminderKind;
import '../models/goal.dart' show normalizeUserSelectableReminderKind;
import '../services/alarm_service.dart';
import '../services/local_notifications.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

Future<void> showCountdownEditor(
  BuildContext context, {
  required CountdownItem item,
  bool showDelete = true,
}) {
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => _CountdownEditSheet(item: item, showDelete: showDelete),
  );
}

ButtonStyle _countdownDangerTextButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return TextButton.styleFrom(
    foregroundColor: cs.error,
    textStyle: appSecondaryControlTextStyle(context),
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

ButtonStyle _countdownDangerFilledButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: cs.error,
    foregroundColor: cs.onError,
    textStyle: appSecondaryMenuItemTextStyle(context),
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class CountdownScreen extends StatefulWidget {
  final String? initialCountdownId;

  const CountdownScreen({super.key, this.initialCountdownId});

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  bool _openedInitialCountdown = false;

  void _showEditor(BuildContext context, {required CountdownItem item}) {
    showCountdownEditor(context, item: item);
  }

  void _showNewEditor(BuildContext context) {
    final now = AppClock.now();
    showCountdownEditor(
      context,
      showDelete: false,
      item: CountdownItem(
        id: 'countdown-${now.microsecondsSinceEpoch}',
        title: '',
        targetDate: DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1)),
        category: I18n.tr('countdown.category.default'),
      ),
    );
  }

  void _openInitialCountdownIfNeeded(List<CountdownItem> items) {
    if (_openedInitialCountdown) return;
    final id = widget.initialCountdownId;
    if (id == null || id.isEmpty) return;
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _openedInitialCountdown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showEditor(context, item: items[index]);
    });
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final provider = context.watch<CountdownProvider>();
    final routeTitleStyle = appSecondaryRouteTitleTextStyle(context);
    final items = [...provider.items]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return a.daysRemaining.compareTo(b.daysRemaining);
      });
    _openInitialCountdownIfNeeded(items);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final upcoming = items.where((item) => item.daysRemaining >= 0).toList()
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    final nearest = upcoming.isNotEmpty ? upcoming.first : null;
    final soonCount = upcoming.where((item) => item.daysRemaining <= 7).length;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('countdown.title')),
        titleTextStyle: routeTitleStyle,
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('countdown_add_button'),
        tooltip: I18n.tr('countdown.title'),
        onPressed: () => _showNewEditor(context),
        icon: const Icon(Icons.add),
        label: Text(I18n.tr('action.add')),
        backgroundColor: cs.primary,
      ),
      body: AppSecondaryControlTheme(
        child: items.isEmpty
            ? EmptyState(
                icon: Icons.event,
                message: I18n.tr('countdown.empty'),
                actionLabel: I18n.tr('action.add'),
                onAction: () => _showNewEditor(context),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                children: [
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.event, color: cs.primary, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                I18n.tr('countdown.title'),
                                style: routeTitleStyle,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                nearest == null
                                    ? I18n.tr('countdown.nearest.empty')
                                    : '${I18n.tr('countdown.nearest.prefix')}${nearest.title} · '
                                          '${I18n.tr('countdown.nearest.days_prefix')}${nearest.daysRemaining} '
                                          '${I18n.tr('unit.day')}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.68,
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 10),
                              _CountdownSummaryStats(
                                total: _SummaryStat(
                                  key: const ValueKey(
                                    'countdown_summary_total',
                                  ),
                                  label: I18n.tr('countdown.summary.total'),
                                  value: '${items.length}',
                                  color: cs.primary,
                                ),
                                soon: _SummaryStat(
                                  key: const ValueKey(
                                    'countdown_summary_within_7_days',
                                  ),
                                  label: I18n.tr(
                                    'countdown.summary.within_7_days',
                                  ),
                                  value: '$soonCount',
                                  color: cs.tertiary,
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
                    title: I18n.tr('countdown.list.title'),
                    subtitle: I18n.tr('countdown.list.subtitle'),
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                  ),
                  ...items.map(
                    (item) => _CountdownCard(
                      item: item,
                      onTap: () => _showEditor(context, item: item),
                      onTogglePin: () => provider.togglePin(item.id),
                      onDelete: () => provider.deleteItem(item.id),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CountdownEditSheet extends StatefulWidget {
  final CountdownItem item;
  final bool showDelete;

  const _CountdownEditSheet({required this.item, required this.showDelete});

  @override
  State<_CountdownEditSheet> createState() => _CountdownEditSheetState();
}

class _CountdownEditSheetState extends State<_CountdownEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _categoryCtrl;
  late DateTime _targetDate;
  late bool _remind;
  late int _remindDaysBefore;
  late TimeOfDay _remindTime;
  late ReminderKind _reminderKind;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleCtrl = TextEditingController(text: item.title);
    _categoryCtrl = TextEditingController(text: item.category);
    _targetDate = item.targetDate;
    _remind = item.remind;
    _remindDaysBefore = item.remindDaysBefore;
    _remindTime = TimeOfDay(hour: item.remindHour, minute: item.remindMinute);
    _reminderKind = normalizeUserSelectableReminderKind(item.reminderKind);
    if (_reminderKind == ReminderKind.off) {
      _remind = false;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  DateTime _remindAtFor(CountdownItem item) {
    return AppClock.date(
      item.targetDate.year,
      item.targetDate.month,
      item.targetDate.day - item.remindDaysBefore,
      item.remindHour,
      item.remindMinute,
    );
  }

  Future<_ReminderPreflightResult> _checkReminderBeforeSave(
    CountdownItem item,
    DateTime remindAt,
  ) async {
    final issueTitle = I18n.tr('countdown.reminder.register_failed');
    try {
      switch (item.reminderKind) {
        case ReminderKind.push:
          final notif = context.read<NotificationService?>();
          final ready =
              await notif
                  ?.ensureReadyForReminder(
                    scheduledTime: remindAt,
                    issueTitle: issueTitle,
                    relatedId: item.id,
                  )
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => false,
                  ) ??
              true;
          if (ready) return const _ReminderPreflightResult.ok();
          final issue = notif?.lastScheduleIssue;
          return _ReminderPreflightResult.disabled(
            issue == null
                ? I18n.tr('countdown.reminder.not_registered')
                : '${I18n.tr('countdown.reminder.not_registered_prefix')}${issue.message}',
          );
        case ReminderKind.popup:
          final notif = context.read<NotificationService?>();
          final ready =
              await notif
                  ?.ensureReadyForReminder(
                    scheduledTime: remindAt,
                    issueTitle: I18n.tr(
                      'countdown.reminder.popup_fallback_failed',
                    ),
                    relatedId: item.id,
                  )
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => false,
                  ) ??
              await LocalNotifications.instance.ensurePermission().timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              );
          if (!ready) {
            final issue = notif?.lastScheduleIssue;
            return _ReminderPreflightResult.disabled(
              issue == null
                  ? I18n.tr('countdown.reminder.popup_permission_denied')
                  : '${I18n.tr('countdown.reminder.popup_not_registered_prefix')}${issue.message}',
            );
          }
          return _ReminderPreflightResult.warning(
            I18n.tr('countdown.reminder.popup_warning'),
          );
        case ReminderKind.alarm:
          final notificationGranted = await LocalNotifications.instance
              .ensurePermission()
              .timeout(const Duration(seconds: 5), onTimeout: () => false);
          if (!notificationGranted) {
            return _ReminderPreflightResult.disabled(
              I18n.tr('countdown.reminder.alarm_permission_denied'),
            );
          }
          final warnings = <String>[];
          final channelIds = await AlarmService.instance
              .notificationChannelIds();
          if (channelIds != null &&
              channelIds.isNotEmpty &&
              !channelIds.contains(AlarmService.channelId)) {
            warnings.add(I18n.tr('countdown.reminder.alarm_channel_missing'));
          }
          final exactGranted = await AlarmService.instance
              .hasExactAlarmPermission();
          if (!exactGranted) {
            warnings.add(I18n.tr('countdown.reminder.exact_alarm_missing'));
          }
          final fullScreenGranted = await AlarmService.instance
              .hasFullScreenIntentPermission();
          if (!fullScreenGranted) {
            warnings.add(I18n.tr('countdown.reminder.fullscreen_missing'));
          }
          if (warnings.isEmpty) return const _ReminderPreflightResult.ok();
          return _ReminderPreflightResult.warning(
            '${I18n.tr('countdown.reminder.saved_with_warnings_prefix')}${warnings.join('; ')}。',
          );
        case ReminderKind.email:
          return _ReminderPreflightResult.warning(
            I18n.tr('countdown.reminder.email_warning'),
          );
        case ReminderKind.off:
          return const _ReminderPreflightResult.ok();
      }
    } catch (e) {
      return _ReminderPreflightResult.disabled(
        '${I18n.tr('countdown.reminder.exception_prefix')}$e',
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('countdown.validation.title_required')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final category = _categoryCtrl.text.trim().isEmpty
        ? I18n.tr('countdown.category.default')
        : _categoryCtrl.text.trim();
    final provider = context.read<CountdownProvider>();
    var reminderWarning = '';
    var next = CountdownItem(
      id: widget.item.id,
      title: title,
      targetDate: _targetDate,
      isPinned: widget.item.isPinned,
      category: category,
      remind: _remind,
      remindDaysBefore: _remindDaysBefore,
      remindHour: _remindTime.hour,
      remindMinute: _remindTime.minute,
      reminderKind: _remind ? _reminderKind : ReminderKind.off,
    );
    if (next.remind) {
      final remindAt = _remindAtFor(next);
      if (!remindAt.isAfter(AppClock.now())) {
        reminderWarning = I18n.tr('countdown.reminder.time_past');
        next = next.copyWith(remind: false, reminderKind: ReminderKind.off);
        setState(() => _remind = false);
      }
    }
    if (next.remind) {
      final preflight = await _checkReminderBeforeSave(
        next,
        _remindAtFor(next),
      );
      if (!mounted) {
        _saving = false;
        return;
      }
      if (preflight.message.isNotEmpty) {
        reminderWarning = preflight.message;
      }
      if (preflight.disableReminder) {
        next = next.copyWith(remind: false, reminderKind: ReminderKind.off);
        setState(() => _remind = false);
      }
    }
    try {
      await provider.updateItem(next);
    } catch (e) {
      if (!mounted) {
        _saving = false;
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${I18n.tr('countdown.save_failed_prefix')}$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) {
      _saving = false;
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final feedback = reminderWarning.isNotEmpty
        ? reminderWarning
        : I18n.tr('countdown.saved');
    Navigator.pop(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(feedback),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(dialogCtx).colorScheme.error,
        ),
        title: Text(I18n.tr('anniversary.delete.title')),
        content: Text(
          '"${widget.item.title}" ${I18n.tr('anniversary.delete.content_suffix')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            style: _countdownDangerFilledButtonStyle(dialogCtx),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(I18n.tr('action.delete')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await context.read<CountdownProvider>().deleteItem(widget.item.id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final targetText = I18nDateFormat.date(_targetDate);
    final timeText = I18nDateFormat.timeOfDay(
      hour: _remindTime.hour,
      minute: _remindTime.minute,
    );
    return AppModalSheet(
      title: widget.item.title.trim().isEmpty
          ? I18n.tr('countdown.title')
          : I18n.tr('countdown.editor.edit_title'),
      subtitle: I18n.tr('countdown.editor.subtitle'),
      leadingActions: widget.showDelete
          ? [
              TextButton.icon(
                onPressed: _delete,
                style: _countdownDangerTextButtonStyle(context),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(I18n.tr('action.delete')),
              ),
            ]
          : const [],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          key: const ValueKey('countdown_editor_save_button'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(I18n.tr('action.save')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: I18n.tr('countdown.field.title'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            decoration: InputDecoration(
              labelText: I18n.tr('countdown.field.category'),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(I18n.tr('countdown.field.target_date')),
            subtitle: Text(targetText),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await AppDatePicker.pickSolar(
                context,
                initialDate: _targetDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                title: I18n.tr('countdown.field.target_date'),
              );
              if (!mounted) return;
              if (picked != null) {
                setState(() => _targetDate = picked);
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _remind,
            title: Text(I18n.tr('countdown.field.due_reminder')),
            subtitle: Text(
              _remind
                  ? '${I18n.tr('countdown.reminder.before_prefix')}$_remindDaysBefore'
                        '${I18n.tr('countdown.reminder.before_suffix')} · $timeText'
                  : I18n.tr('countdown.reminder.closed'),
            ),
            onChanged: (v) => setState(() => _remind = v),
          ),
          if (_remind) ...[
            SingleChildScrollView(
              key: const ValueKey('countdown_reminder_kind_scroll'),
              scrollDirection: Axis.horizontal,
              child: AppSecondaryControlTheme(
                child: SegmentedButton<ReminderKind>(
                  segments: [
                    ButtonSegment(
                      value: ReminderKind.push,
                      icon: const Icon(Icons.notifications_outlined),
                      label: Text(I18n.tr('reminder.kind.push')),
                    ),
                    ButtonSegment(
                      value: ReminderKind.popup,
                      icon: const Icon(Icons.open_in_new_outlined),
                      label: Text(I18n.tr('reminder.kind.popup')),
                    ),
                    ButtonSegment(
                      value: ReminderKind.alarm,
                      icon: const Icon(Icons.alarm_outlined),
                      label: Text(I18n.tr('reminder.kind.alarm')),
                    ),
                    ButtonSegment(
                      value: ReminderKind.off,
                      icon: const Icon(Icons.notifications_off_outlined),
                      label: Text(I18n.tr('reminder.kind.off')),
                    ),
                  ],
                  selected: {_reminderKind},
                  onSelectionChanged: (selected) => setState(() {
                    _reminderKind = selected.first;
                    if (_reminderKind == ReminderKind.off) {
                      _remind = false;
                    }
                  }),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 4),
                Text(I18n.tr('countdown.field.remind_days')),
                Expanded(
                  child: Slider(
                    value: _remindDaysBefore.toDouble(),
                    min: 0,
                    max: 30,
                    divisions: 30,
                    label: '$_remindDaysBefore',
                    onChanged: (v) =>
                        setState(() => _remindDaysBefore = v.toInt()),
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(I18n.tr('countdown.field.remind_time')),
              subtitle: Text(timeText),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await AppTimePicker.show(
                  context,
                  initialTime: _remindTime,
                  title: I18n.tr('countdown.field.remind_time'),
                  minuteStep: 5,
                );
                if (!mounted) return;
                if (picked != null) {
                  setState(() => _remindTime = picked);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ReminderPreflightResult {
  final bool disableReminder;
  final String message;

  const _ReminderPreflightResult._({
    required this.disableReminder,
    required this.message,
  });

  const _ReminderPreflightResult.ok()
    : this._(disableReminder: false, message: '');

  const _ReminderPreflightResult.warning(String message)
    : this._(disableReminder: false, message: message);

  const _ReminderPreflightResult.disabled(String message)
    : this._(disableReminder: true, message: message);
}

class _CountdownSummaryStats extends StatelessWidget {
  final _SummaryStat total;
  final _SummaryStat soon;

  const _CountdownSummaryStats({required this.total, required this.soon});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 220.0;
        final statWidth = width >= 176 ? ((width - 14) / 2) : width;
        return Wrap(
          spacing: 14,
          runSpacing: 10,
          children: [
            SizedBox(width: statWidth, child: total),
            SizedBox(width: statWidth, child: soon),
          ],
        );
      },
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryStat({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.numbers, size: 15, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: appSecondaryRouteTitleTextStyle(context).copyWith(
            fontWeight: DesignTokens.fontWeightStrong,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.62),
            fontWeight: DesignTokens.fontWeightStrong,
          ),
        ),
      ],
    );
  }
}

class _CountdownCard extends StatefulWidget {
  final CountdownItem item;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final Future<void> Function() onDelete;

  const _CountdownCard({
    required this.item,
    required this.onTap,
    required this.onTogglePin,
    required this.onDelete,
  });

  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard> {
  static const double _swipeActionWidth = 82;
  static const double _swipeOpenThreshold = 32;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;

  @override
  void didUpdateWidget(covariant _CountdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.id != oldWidget.item.id) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(dialogCtx).colorScheme.error,
        ),
        title: Text(I18n.tr('anniversary.delete.title')),
        content: Text(
          '"${widget.item.title}" ${I18n.tr('anniversary.delete.content_suffix')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            style: _countdownDangerFilledButtonStyle(dialogCtx),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(I18n.tr('action.delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onDelete();
    } else {
      _closeSwipe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cs = Theme.of(context).colorScheme;
    final isPast = item.daysRemaining < 0;
    final absDays = item.daysRemaining.abs();
    final color = isPast
        ? Colors.grey
        : (item.daysRemaining <= 3 ? cs.error : cs.primary);
    final status = item.isPinned
        ? I18n.tr('countdown.status.pinned')
        : isPast
        ? I18n.tr('countdown.status.expired')
        : item.daysRemaining <= 3
        ? I18n.tr('countdown.status.soon')
        : I18n.tr('countdown.status.running');
    final titleStyle = appSecondaryRouteTitleTextStyle(context);
    final metaStyle = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurface.withValues(alpha: 0.62));

    final content = InkWell(
      onTap: _swipeOpen ? _closeSwipe : widget.onTap,
      onLongPress: widget.onTogglePin,
      borderRadius: BorderRadius.circular(14),
      child: AppSurfaceCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
        child: Stack(
          children: [
            Positioned.fill(
              right: null,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isPast ? 0.42 : 0.72),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.isPinned)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.push_pin,
                                  size: 14,
                                  color: color,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _StatusPill(label: status, color: color),
                            _StatusPill(
                              label: item.category,
                              color: cs.tertiary,
                            ),
                            if (item.remind)
                              _StatusPill(
                                label:
                                    '${I18n.tr('countdown.reminder.before_prefix')}'
                                    '${item.remindDaysBefore}'
                                    '${I18n.tr('countdown.reminder.before_suffix')} '
                                    '${I18nDateFormat.timeOfDay(hour: item.remindHour, minute: item.remindMinute)}',
                                color: cs.primary,
                                icon: Icons.notifications_active_outlined,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${I18n.tr('countdown.target.prefix')}'
                          '${I18nDateFormat.date(item.targetDate)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 54,
                      maxWidth: 108,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isPast
                              ? I18n.tr('countdown.days.elapsed')
                              : I18n.tr('countdown.days.remaining'),
                          style: metaStyle.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.54),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$absDays',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: DesignTokens.fontWeightStrong,
                                color: color,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              I18n.tr('unit.day'),
                              style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight: DesignTokens.fontWeightStrong,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      key: ValueKey('countdown_card_${item.id}'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (details) {
        final next = (_swipeOffset - details.delta.dx).clamp(
          0.0,
          _swipeActionWidth,
        );
        if (next == _swipeOffset) return;
        setState(() => _swipeOffset = next);
      },
      onHorizontalDragEnd: (_) {
        final shouldOpen = _swipeOffset >= _swipeOpenThreshold;
        setState(() {
          _dragging = false;
          _swipeOffset = shouldOpen ? _swipeActionWidth : 0;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dragging = false;
        _swipeOffset = _swipeOffset >= _swipeOpenThreshold
            ? _swipeActionWidth
            : 0;
      }),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_swipeOffset > 0)
            Positioned.fill(
              child: _CountdownInlineSwipeActions(
                margin: const EdgeInsets.only(bottom: 12),
                onDelete: () => _confirmDelete(context),
              ),
            ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
            child: content,
          ),
        ],
      ),
    );
  }
}

class _CountdownInlineSwipeActions extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final VoidCallback onDelete;

  const _CountdownInlineSwipeActions({
    required this.margin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: _CountdownCardState._swipeActionWidth,
        height: double.infinity,
        child: _CountdownInlineSwipeButton(
          key: const ValueKey('countdown_swipe_delete_button'),
          icon: Icons.delete_outline,
          label: I18n.tr('action.delete'),
          background: cs.errorContainer.withValues(alpha: 0.86),
          foreground: cs.onErrorContainer,
          onTap: onDelete,
        ),
      ),
    );
  }
}

class _CountdownInlineSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _CountdownInlineSwipeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground,
      fontWeight: DesignTokens.fontWeightStrong,
      height: 1.1,
    );
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _StatusPill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final maxWidth = (MediaQuery.sizeOf(context).width - 120)
        .clamp(96.0, 180.0)
        .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.10), width: 0.45),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
