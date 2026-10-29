import '../models/todo.dart';
import '../providers/todo_provider.dart';
import '../widgets/pomodoro_task_picker.dart';
import '../core/app_clock.dart';
import '../widgets/app_page_tabs.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/design_tokens.dart';
import '../widgets/apple_page_frame.dart';
import '../core/focus_report.dart';
import '../core/focus_sound_catalog.dart';
import '../models/focus_room.dart';
import '../models/pomodoro.dart';
import '../providers/custom_focus_sound_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/focus_room_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_client.dart';
import '../services/focus_room_api.dart';
import '../services/focus_sound_service.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/brand_background.dart';
import '../widgets/pomodoro_timer_ring.dart';
import '../widgets/pomodoro_session_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import '../core/i18n.dart';
import '../widgets/focus_distraction_app_picker.dart';

String _focusRoomErrorText(Object error) {
  final message = error is ApiException ? error.message : error.toString();
  if (isFocusRoomRealtimeTransportError(error)) {
    return focusRoomRankingUnavailableMessage;
  }
  if (isBackendCompatibilityDiagnosticMessage(message)) return message;
  return userVisibleApiError(error, fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。');
}

Future<void> showPomodoroSessionEditor(
  BuildContext context,
  PomodoroSession session,
) async {
  final provider = context.read<PomodoroProvider>();
  final rooms =
      context.read<FocusRoomProvider?>()?.rooms ?? const <FocusRoom>[];
  final customProvider = context.read<CustomFocusSoundProvider?>();
  final customSounds = customProvider?.sounds ?? const <CustomFocusSound>[];
  final taskCtrl = TextEditingController(text: session.taskName ?? '');
  final tagCtrl = TextEditingController(text: session.tag ?? '');
  final durationCtrl = TextEditingController(
    text: (session.durationSeconds ~/ 60).clamp(1, 24 * 60).toString(),
  );
  final localStart = AppClock.toLocal(session.startTime);
  var date = AppClock.dateOnly(localStart);
  var startTime = TimeOfDay.fromDateTime(localStart);
  var selectedType = session.type;
  var selectedSound = session.whiteNoiseSound.trim().isEmpty
      ? FocusSoundCatalog.none
      : session.whiteNoiseSound;
  var selectedRoomId = rooms.any((room) => room.id == session.focusRoomId)
      ? session.focusRoomId
      : null;

  DateTime combineStart() => AppClock.date(
    date.year,
    date.month,
    date.day,
    startTime.hour,
    startTime.minute,
  );

  try {
    await showAppModalSheet<void>(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSt) {
          AppClock.watch(sheetCtx);
          Future<void> previewSound(String value) async {
            setSt(() => selectedSound = value);
            if (value == FocusSoundCatalog.none) {
              await FocusSoundService.instance.stop();
              return;
            }
            await FocusSoundService.instance.setVolume(
              provider.config.focusSoundVolume,
            );
            final started = await FocusSoundService.instance.preview(value);
            if (!started && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('专注声音预览启动失败，请检查系统音量或音频资源'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }

          Future<void> save() async {
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(sheetCtx);
            final minutes = int.tryParse(durationCtrl.text.trim()) ?? 0;
            if (minutes < 1 || minutes > 24 * 60) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('专注时长需在 1-1440 分钟之间'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            final start = combineStart();
            final next = session.copyWith(
              startTime: start.toUtc(),
              endTime: start.add(Duration(minutes: minutes)).toUtc(),
              durationSeconds: minutes * 60,
              type: selectedType,
              taskName: taskCtrl.text.trim().isEmpty
                  ? null
                  : taskCtrl.text.trim(),
              clearTaskName: taskCtrl.text.trim().isEmpty,
              clearTaskLink: taskCtrl.text.trim() != (session.taskName ?? ''),
              tag: tagCtrl.text.trim().isEmpty ? null : tagCtrl.text.trim(),
              clearTag: tagCtrl.text.trim().isEmpty,
              whiteNoiseSound: selectedSound,
              focusRoomId: selectedRoomId,
              clearFocusRoomId: selectedRoomId == null,
            );
            final ok = await provider.updateSession(next);
            if (!ok) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('这条会话不存在或已被删除'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            if (!context.mounted || !sheetCtx.mounted) return;
            navigator.pop();
            messenger.showSnackBar(
              const SnackBar(
                content: Text('已保存专注会话'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(milliseconds: 1200),
              ),
            );
          }

          return AppModalSheet(
            title: '编辑专注会话',
            subtitle: '同步更新番茄钟历史和时间足迹',
            shiftForKeyboard: true,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(onPressed: save, child: const Text('保存')),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: taskCtrl,
                  decoration: const InputDecoration(
                    labelText: '任务名',
                    prefixIcon: Icon(Icons.task_alt_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tagCtrl,
                  decoration: const InputDecoration(
                    labelText: '标签',
                    prefixIcon: Icon(Icons.sell_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: const Text('日期'),
                        subtitle: Text(
                          '${date.year}/${date.month}/${date.day}',
                        ),
                        onTap: () async {
                          final picked = await AppDatePicker.pickSolar(
                            sheetCtx,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2099, 12, 31),
                            title: '会话日期',
                          );
                          if (picked == null) return;
                          setSt(() {
                            date = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                            );
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('开始时间'),
                        subtitle: Text(AppTimePicker.format(startTime)),
                        onTap: () async {
                          final picked = await AppTimePicker.show(
                            sheetCtx,
                            initialTime: startTime,
                            title: '开始时间',
                            minuteStep: 5,
                          );
                          if (picked == null) return;
                          setSt(() => startTime = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '时长（分钟）',
                    prefixIcon: Icon(Icons.hourglass_bottom_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<PomodoroType>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: PomodoroType.focus,
                      label: Text('专注'),
                      icon: Icon(Icons.timer_outlined),
                    ),
                    ButtonSegment(
                      value: PomodoroType.shortBreak,
                      label: Text('短休'),
                      icon: Icon(Icons.free_breakfast_outlined),
                    ),
                    ButtonSegment(
                      value: PomodoroType.longBreak,
                      label: Text('长休'),
                      icon: Icon(Icons.weekend_outlined),
                    ),
                  ],
                  selected: {selectedType},
                  onSelectionChanged: (value) =>
                      setSt(() => selectedType = value.first),
                ),
                const SizedBox(height: 12),
                AppDropdownField<String>(
                  initialValue: selectedSound,
                  decoration: const InputDecoration(
                    labelText: '白噪音',
                    prefixIcon: Icon(Icons.music_note_outlined),
                  ),
                  items: [
                    for (final option in FocusSoundCatalog.options)
                      DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                    for (final sound in customSounds)
                      DropdownMenuItem(
                        value: sound.id,
                        child: Text(sound.label),
                      ),
                    if (selectedSound != FocusSoundCatalog.none &&
                        !FocusSoundCatalog.options.any(
                          (option) => option.id == selectedSound,
                        ) &&
                        !customSounds.any((sound) => sound.id == selectedSound))
                      DropdownMenuItem(
                        value: selectedSound,
                        child: Text(
                          selectedSound.startsWith(
                                CustomFocusSoundProvider.idPrefix,
                              )
                              ? (customProvider?.labelFor(selectedSound) ??
                                    '自定义音频')
                              : selectedSound,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      previewSound(value ?? FocusSoundCatalog.none),
                ),
                const SizedBox(height: 10),
                AppDropdownField<String>(
                  initialValue: selectedRoomId ?? '',
                  decoration: const InputDecoration(
                    labelText: '自习室',
                    prefixIcon: Icon(Icons.meeting_room_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('不关联自习室')),
                    for (final room in rooms)
                      DropdownMenuItem(value: room.id, child: Text(room.name)),
                  ],
                  onChanged: (value) => setSt(
                    () => selectedRoomId = value == null || value.isEmpty
                        ? null
                        : value,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  } finally {
    taskCtrl.dispose();
    tagCtrl.dispose();
    durationCtrl.dispose();
  }
}

class PomodoroScreen extends StatelessWidget {
  final bool useShellBackground;

  const PomodoroScreen({super.key, this.useShellBackground = false});

  @override
  Widget build(BuildContext context) {
    if (context.read<PomodoroProvider?>() == null ||
        context.read<FocusRoomProvider?>() == null ||
        context.read<ThemeProvider?>() == null ||
        context.read<CustomFocusSoundProvider?>() == null ||
        context.read<AuthProvider?>() == null) {
      return _PomodoroProviderFallback(
        child: _PomodoroScreenBody(useShellBackground: useShellBackground),
      );
    }
    return _PomodoroScreenBody(useShellBackground: useShellBackground);
  }
}

class _PomodoroScreenBody extends StatefulWidget {
  final bool useShellBackground;

  const _PomodoroScreenBody({this.useShellBackground = false});

  @override
  State<_PomodoroScreenBody> createState() => _PomodoroScreenState();
}

class _PomodoroProviderFallback extends StatefulWidget {
  final Widget child;

  const _PomodoroProviderFallback({required this.child});

  @override
  State<_PomodoroProviderFallback> createState() =>
      _PomodoroProviderFallbackState();
}

class _PomodoroProviderFallbackState extends State<_PomodoroProviderFallback> {
  late final PomodoroProvider _pomodoro = PomodoroProvider();
  late final ThemeProvider _theme = ThemeProvider();
  late final FocusRoomProvider _rooms = FocusRoomProvider();
  late final CustomFocusSoundProvider _customSounds =
      CustomFocusSoundProvider();
  late final AuthProvider _auth = AuthProvider();

  @override
  void initState() {
    super.initState();
    _pomodoro.attachLifecycle();
    unawaited(_pomodoro.loadFromStorage());
    unawaited(_rooms.loadFromStorage());
    unawaited(_customSounds.loadFromStorage());
  }

  @override
  void dispose() {
    _pomodoro.dispose();
    _theme.dispose();
    _rooms.dispose();
    _customSounds.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PomodoroProvider>.value(value: _pomodoro),
        ChangeNotifierProvider<ThemeProvider>.value(value: _theme),
        ChangeNotifierProvider<FocusRoomProvider>.value(value: _rooms),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(
          value: _customSounds,
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
      ],
      child: widget.child,
    );
  }
}

class _PomodoroDialogBody extends StatelessWidget {
  final Widget child;

  const _PomodoroDialogBody({required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = (media.size.height - media.viewInsets.bottom - 180)
        .clamp(220.0, 520.0)
        .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
      child: AppSecondaryControlTheme(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: child,
        ),
      ),
    );
  }
}

class _PomodoroScreenState extends State<_PomodoroScreenBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pomodoro = context.read<PomodoroProvider>();
      final rooms = context.read<FocusRoomProvider>();
      pomodoro.refreshFocusDndStatus();
      if (pomodoro.state.focusRoomId == null && rooms.activeRoomId != null) {
        unawaited(pomodoro.setFocusRoomId(rooms.activeRoomId));
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _typeColor(PomodoroType t) {
    switch (t) {
      case PomodoroType.focus:
        return const Color(0xFFE53935);
      case PomodoroType.shortBreak:
        return const Color(0xFF4CAF50);
      case PomodoroType.longBreak:
        return const Color(0xFF2196F3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;

    String typeLabel(PomodoroType t) {
      switch (t) {
        case PomodoroType.focus:
          return s.focusStateFocus;
        case PomodoroType.shortBreak:
          return s.focusStateShortBreak;
        case PomodoroType.longBreak:
          return s.focusStateLongBreak;
      }
    }

    final appleLayout = usesApplePageLayout(context);
    final focusTabs = AppPageTabs(
      controller: _tabCtrl,
      height: AppPageTabs.heightFor(context),
      tabs: [
        Tab(text: s.focusTabTimer),
        Tab(text: s.focusTabHistory),
        const Tab(text: '自习室'),
      ],
    );

    return _MaybePomodoroBackground(
      enabled: !widget.useShellBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 默认主题：没有 AppBar，页头与页签进入页面内容流。
        appBar: appleLayout
            ? null
            : AppBar(title: Text(s.focusTitle), bottom: focusTabs),
        body: SafeArea(
          top: appleLayout,
          bottom: false,
          left: false,
          right: false,
          child: Column(
            children: [
              if (appleLayout) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ApplePageFrame.gutter,
                    ApplePageFrame.pageTop,
                    ApplePageFrame.gutter,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: ApplePageFrame.maxContentWidth,
                      ),
                      child: ApplePageHeader(title: s.focusTitle),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ApplePageFrame.gutter,
                    DesignTokens.spaceSm,
                    ApplePageFrame.gutter,
                    DesignTokens.spaceXs,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: ApplePageFrame.maxContentWidth,
                      ),
                      child: focusTabs,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    Consumer<PomodoroProvider>(
                      builder: (context, provider, _) {
                        final state = provider.state;
                        final themeProvider = context.watch<ThemeProvider>();
                        final s = themeProvider.brand.strings;
                        final focusBackdrop = themeProvider.activeFocusBackdrop;
                        final color = _typeColor(state.type);
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final availableHeight = constraints.maxHeight;
                            final compact = availableHeight < 660;
                            final tight = availableHeight < 560;
                            final ringSize = tight
                                ? 126.0
                                : compact
                                ? 148.0
                                : 172.0;
                            final appleLayout = usesApplePageLayout(context);
                            final cardPadding = appleLayout
                                ? EdgeInsets.all(
                                    tight ? 14 : (compact ? 18 : 22),
                                  )
                                : tight
                                ? const EdgeInsets.all(10)
                                : compact
                                ? const EdgeInsets.all(12)
                                : const EdgeInsets.all(14);
                            final contentWidth = (constraints.maxWidth - 24)
                                .clamp(0.0, 720.0)
                                .toDouble();
                            final cs = Theme.of(context).colorScheme;
                            // 默认主题：默认专注背景不再叠渐变噪声，只保留用户自选的
                            // 非默认 focus backdrop 渐变。
                            final Gradient? cardGradient =
                                focusBackdrop.id ==
                                    ThemeProvider.defaultFocusBackdropId
                                ? (appleLayout
                                      ? null
                                      : LinearGradient(
                                          colors: [
                                            color.withValues(alpha: 0.14),
                                            cs.surface,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ))
                                : LinearGradient(
                                    colors: [
                                      focusBackdrop.colors.first.withValues(
                                        alpha: 0.22,
                                      ),
                                      focusBackdrop.colors.last.withValues(
                                        alpha: 0.14,
                                      ),
                                      cs.surface,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  );

                            final card = AppSurfaceCard(
                              padding: cardPadding,
                              gradient: cardGradient,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: tight ? 38 : 44,
                                        height: tight ? 38 : 44,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.timer_outlined,
                                          color: color,
                                          size: tight ? 22 : 24,
                                        ),
                                      ),
                                      if (focusBackdrop.id !=
                                          ThemeProvider
                                              .defaultFocusBackdropId) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: tight ? 7 : 9,
                                            vertical: tight ? 4 : 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: focusBackdrop.colors.first
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                focusBackdrop.icon,
                                                size: 13,
                                                color:
                                                    focusBackdrop.colors.first,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                focusBackdrop.name,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: focusBackdrop
                                                      .colors
                                                      .first,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              typeLabel(state.type),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontSize: tight ? 15 : 17,
                                                    color: cs.onSurface,
                                                    fontWeight: DesignTokens
                                                        .fontWeightStrong,
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${state.completedSessions} ${s.focusCompletedSuffix}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: cs.onSurface
                                                        .withValues(
                                                          alpha: 0.68,
                                                        ),
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: tight ? 8 : 10,
                                          vertical: tight ? 4 : 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          state.isRunning ? '进行中' : '已暂停',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight:
                                                DesignTokens.fontWeightStrong,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: tight ? 6 : 10),
                                  _PomodoroLiveTimer(
                                    provider: provider,
                                    color: color,
                                    ringSize: ringSize,
                                    tight: tight,
                                    completedSuffix: s.focusCompletedSuffix,
                                    timerLabel: s.focusTabTimer,
                                    textColor: cs.onSurface.withValues(
                                      alpha: 0.64,
                                    ),
                                    formatTime: _formatTime,
                                  ),
                                  if (state.taskName != null &&
                                      state.taskName!.isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: tight ? 5 : 7,
                                      ),
                                      child: Center(
                                        child: GestureDetector(
                                          onTap: () => _editTaskName(
                                            context,
                                            provider,
                                            state.taskName!,
                                          ),
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width -
                                                  96,
                                            ),
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: tight ? 8 : 10,
                                                vertical: tight ? 4 : 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: cs
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.75),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.assignment_outlined,
                                                    size: 14,
                                                    color: cs.onSurface
                                                        .withValues(
                                                          alpha: 0.64,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      state.taskLabel!,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: cs.onSurface
                                                            .withValues(
                                                              alpha: 0.72,
                                                            ),
                                                        fontSize: 12,
                                                        fontWeight: DesignTokens
                                                            .fontWeightStrong,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  SizedBox(height: tight ? 6 : 9),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: ChoiceChip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            avatar: const Icon(
                                              Icons.timer_outlined,
                                            ),
                                            label: const Text('自由计时'),
                                            selected: state.isCountUp,
                                            onSelected: state.isRunning
                                                ? null
                                                : (_) => provider
                                                      .setCountUpMode(true),
                                          ),
                                        ),
                                        ...[15, 25, 30, 45, 60, 90].map(
                                          (min) => Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: ChoiceChip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              label: Text('$min 分钟'),
                                              selected:
                                                  !state.isCountUp &&
                                                  state.totalSeconds ==
                                                      min * 60 &&
                                                  state.type ==
                                                      PomodoroType.focus,
                                              onSelected: state.isRunning
                                                  ? null
                                                  : (_) {
                                                      provider.setCountUpMode(
                                                        false,
                                                      );
                                                      provider.setConfig(
                                                        provider.config
                                                          ..focusDuration =
                                                              min * 60,
                                                      );
                                                    },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 默认主题：任务 / 白噪音 / 免打扰 / 严格专注 / 自习室收进
                                  // 一张轻量组面；其他主题原样透传，不额外包容器。
                                  AppleGroup(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(height: tight ? 6 : 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _FocusControlTile(
                                                icon: Icons.assignment_outlined,
                                                label: '专注任务',
                                                subtitle:
                                                    state
                                                            .taskName
                                                            ?.isNotEmpty ==
                                                        true
                                                    ? state.taskLabel!
                                                    : '选择本轮内容',
                                                color: color,
                                                compact: tight,
                                                onTap: () =>
                                                    _showTaskPresetPicker(
                                                      context,
                                                      provider,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _WhiteNoiseControlTile(
                                                sound: state.whiteNoiseSound,
                                                color:
                                                    state.whiteNoiseSound !=
                                                        'none'
                                                    ? color
                                                    : cs.onSurfaceVariant,
                                                compact: tight,
                                                onTap: () => _showSoundPicker(
                                                  context,
                                                  provider,
                                                  state.whiteNoiseSound,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (provider
                                            .focusDndStatus
                                            .supported) ...[
                                          SizedBox(height: tight ? 6 : 8),
                                          _FocusDndTile(
                                            enabled:
                                                provider.config.autoEnableDnd,
                                            active: provider.focusDndActive,
                                            accessGranted: provider
                                                .focusDndStatus
                                                .accessGranted,
                                            supported: provider
                                                .focusDndStatus
                                                .supported,
                                            compact: tight,
                                            color: color,
                                            onChanged:
                                                provider.setAutoEnableDnd,
                                            onTap: () => _showDndSheet(context),
                                          ),
                                        ],
                                        SizedBox(height: tight ? 6 : 8),
                                        _StrictFocusTile(
                                          enabled:
                                              provider.config.strictFocusMode,
                                          todayCount:
                                              provider.todayPenalties.length,
                                          compact: tight,
                                          color: color,
                                          onChanged:
                                              provider.setStrictFocusMode,
                                          onTap: () =>
                                              _showStrictFocusSheet(context),
                                        ),
                                        SizedBox(height: tight ? 6 : 8),
                                        _ActiveFocusRoomTile(
                                          focusRoomId: state.focusRoomId,
                                          compact: tight,
                                          onTap: () => _showFocusRoomPicker(
                                            context,
                                            provider,
                                            context.read<FocusRoomProvider>(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: tight ? 8 : 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton.filled(
                                        onPressed: () =>
                                            _confirmStrictFocusExit(
                                              context,
                                              FocusPenaltyReason.reset,
                                              provider.resetTimer,
                                            ),
                                        icon: const Icon(Icons.refresh),
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              cs.surfaceContainerHighest,
                                          foregroundColor: cs.onSurface,
                                        ),
                                      ),
                                      SizedBox(width: tight ? 14 : 18),
                                      SizedBox(
                                        width: tight ? 50 : 58,
                                        height: tight ? 50 : 58,
                                        child: FloatingActionButton(
                                          onPressed: provider.toggleTimer,
                                          backgroundColor: color,
                                          child: Icon(
                                            state.isRunning
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            size: tight ? 28 : 30,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: tight ? 14 : 18),
                                      IconButton.filled(
                                        onPressed: state.isCountUp
                                            ? provider.finishCurrentSession
                                            : () => _confirmStrictFocusExit(
                                                context,
                                                FocusPenaltyReason.skip,
                                                provider.skipSession,
                                              ),
                                        icon: Icon(
                                          state.isCountUp
                                              ? Icons.stop
                                              : Icons.skip_next,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              cs.surfaceContainerHighest,
                                          foregroundColor: cs.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );

                            final topPadding = compact ? 6.0 : 8.0;
                            final bottomPadding = compact ? 8.0 : 12.0;
                            final fitHeight =
                                (availableHeight - topPadding - bottomPadding)
                                    .clamp(0.0, double.infinity)
                                    .toDouble();
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                topPadding,
                                12,
                                bottomPadding,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                height: fitHeight,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(
                                    width: contentWidth,
                                    child: card,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    // History tab
                    _HistoryTab(),
                    const _FocusRoomTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _activateRoom(
    PomodoroProvider pomodoro,
    FocusRoomProvider rooms,
    String roomId,
  ) async {
    await rooms.joinRoom(roomId);
    await pomodoro.setFocusRoomId(roomId);
  }

  Future<void> _confirmStrictFocusExit(
    BuildContext context,
    FocusPenaltyReason reason,
    VoidCallback action,
  ) async {
    final provider = context.read<PomodoroProvider>();
    if (!provider.config.strictFocusMode ||
        !provider.state.isRunning ||
        provider.state.type != PomodoroType.focus) {
      action();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('${reason.label}？'),
        content: Text(
          '严格专注已开启。本次操作会记入专注惩罚记录，今日统计和自习室复盘都会显示这次中断。',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续专注'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认记录'),
          ),
        ],
      ),
    );
    if (confirmed == true) action();
  }

  void _showStrictFocusSheet(BuildContext context) {
    showAppModalSheet(
      context: context,
      builder: (ctx) => Consumer<PomodoroProvider>(
        builder: (ctx, provider, _) {
          final cs = Theme.of(ctx).colorScheme;
          final today = provider.todayPenalties;
          final recent = provider.penalties.take(8).toList();
          return AppModalSheet(
            title: '严格专注',
            subtitle: '暂停、跳过、重置、离开应用或打开分心 App 会留下中断记录',
            shiftForKeyboard: true,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('完成'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.lock_clock_outlined),
                  title: const Text('开启严格专注'),
                  subtitle: Text('今日已记录 ${today.length} 次中断'),
                  value: provider.config.strictFocusMode,
                  onChanged: provider.setStrictFocusMode,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.app_blocking_outlined),
                  title: const Text('监控分心应用'),
                  subtitle: Text(
                    provider.focusDistractionStatus.accessibilityGranted
                        ? '辅助功能拦截已授权'
                        : provider.focusDistractionStatus.accessGranted
                        ? '已授权使用情况访问，辅助功能未授权'
                        : '需要 Android 使用情况访问和辅助功能权限',
                  ),
                  value: provider.config.monitorDistractingApps,
                  onChanged: provider.setMonitorDistractingApps,
                ),
                AppSettingsTile(
                  icon: Icons.apps_outlined,
                  color: cs.primary,
                  title: I18n.tr('focus.distraction.tile.title'),
                  subtitle: _distractingAppsSubtitle(provider),
                  onTap: () => _showDistractingAppPicker(ctx, provider),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await provider.openFocusUsageAccessSettings();
                      await provider.refreshFocusDistractionStatus();
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('使用情况权限'),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await provider.openFocusAccessibilitySettings();
                      await provider.refreshFocusDistractionStatus();
                    },
                    icon: const Icon(Icons.accessibility_new_outlined),
                    label: const Text('辅助功能拦截'),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '开启辅助功能后，严格专注运行时会把打开的分心 App 拉回多仪；未授权辅助功能时仍会用使用情况访问记录分心 App 惩罚。',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionHeader(
                  title: '最近惩罚',
                  subtitle: recent.isEmpty ? '暂无记录' : '${recent.length} 条',
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 6),
                if (recent.isEmpty)
                  Text(
                    '保持完整专注后这里会继续为空。',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  )
                else
                  ...recent.map((penalty) => _PenaltyListTile(penalty)),
              ],
            ),
          );
        },
      ),
    );
  }

  String _distractingAppsSubtitle(PomodoroProvider provider) {
    final count = provider.config.distractingAppPackages.length;
    final selected = I18n.tr('focus.distraction.tile.selected');
    if (!provider.config.isDistractionWhitelistMode) {
      return count == 0
          ? I18n.tr('focus.distraction.tile.blacklist_empty')
          : '${I18n.tr('focus.distraction.tile.blacklist')} · $selected $count';
    }
    if (provider.focusDistractionAppScanFailed) {
      return I18n.tr('focus.distraction.tile.whitelist_scan_failed');
    }
    return '${I18n.tr('focus.distraction.tile.whitelist')} · $selected $count';
  }

  Future<void> _showDistractingAppPicker(
    BuildContext context,
    PomodoroProvider provider,
  ) async {
    await showAppModalSheet<void>(
      context: context,
      builder: (ctx) => FocusDistractionAppPicker(
        initialMode: provider.config.distractingAppSelectionMode,
        initialPackages: provider.config.distractingAppPackages,
        loadApps: provider.loadInstalledFocusApps,
        onDone: (mode, packages) async {
          await provider.setDistractingAppSelectionMode(mode);
          await provider.setDistractingAppPackages(packages);
        },
      ),
    );
  }

  void _showFocusRoomPicker(
    BuildContext context,
    PomodoroProvider pomodoro,
    FocusRoomProvider rooms,
  ) {
    showAppModalSheet(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: '选择自习室',
        subtitle: '完成的专注会计入所选自习室本周排行',
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateRoomDialog(context, pomodoro, rooms);
            },
            icon: const Icon(Icons.add),
            label: const Text('新建'),
          ),
          if (pomodoro.state.focusRoomId != null)
            TextButton(
              onPressed: () {
                unawaited(pomodoro.setFocusRoomId(null));
                rooms.setActiveRoom(null);
                Navigator.pop(ctx);
              },
              child: const Text('本轮不加入'),
            ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final room in rooms.rooms)
              _FocusRoomOptionTile(
                room: room,
                joined: rooms.joinedRoomIds.contains(room.id),
                selected: pomodoro.state.focusRoomId == room.id,
                onTap: () async {
                  await _activateRoom(pomodoro, rooms, room.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showCreateRoomDialog(
    BuildContext context,
    PomodoroProvider pomodoro,
    FocusRoomProvider rooms,
  ) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: '300');
    showAppModalSheet<void>(
      context: context,
      builder: (ctx) => AppModalSheet(
        key: const ValueKey('focus_room_create_sheet'),
        title: '新建自习室',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final target = int.tryParse(targetCtrl.text.trim()) ?? 300;
              final room = await rooms.createRoom(
                name: nameCtrl.text,
                description: descCtrl.text,
                weeklyTargetMinutes: target,
              );
              await pomodoro.setFocusRoomId(room.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
        child: AppFormFieldTheme(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: '说明'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: targetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '每周目标（分钟）'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editTaskName(
    BuildContext context,
    PomodoroProvider provider,
    String current,
  ) {
    final s = context.read<ThemeProvider>().brand.strings;
    final ctrl = TextEditingController(text: current);
    final tagCtrl = TextEditingController(text: provider.state.tag ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(s.focusTaskLinkLabel),
        shiftForKeyboard: true,
        content: _PomodoroDialogBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(hintText: '任务名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagCtrl,
                decoration: const InputDecoration(
                  hintText: '标签（用于专注统计分类，可选）',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.setTaskName(null);
              provider.setTag(null);
              Navigator.pop(ctx);
            },
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim() != (provider.state.taskName ?? '')) {
                provider.setTaskName(ctrl.text);
              }
              provider.setTag(tagCtrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  IconData _soundIcon(String sound) => _soundIconForTile(sound);

  static IconData _soundIconForTile(String sound) {
    if (sound.startsWith(CustomFocusSoundProvider.idPrefix)) {
      return Icons.audio_file_outlined;
    }
    final ids = FocusSoundCatalog.trackIdsFor(sound);
    if (ids.length > 1) return Icons.library_music_outlined;
    final single = ids.isEmpty ? sound : ids.first;
    switch (single) {
      case 'rain':
        return Icons.water_drop;
      case 'forest':
        return Icons.park;
      case 'cafe':
        return Icons.local_cafe;
      case 'waves':
        return Icons.waves;
      case 'night_rain':
        return Icons.nights_stay_outlined;
      case 'fan':
        return Icons.air;
      case 'deep_stream':
        return Icons.water;
      case 'thunderstorm':
        return Icons.thunderstorm_outlined;
      case 'storm_rain':
        return Icons.storm_outlined;
      case 'campfire':
        return Icons.local_fire_department_outlined;
      case 'dawn_birds':
        return Icons.wb_twilight_outlined;
      case 'waterfall':
        return Icons.waterfall_chart;
      case 'brook':
        return Icons.stream_outlined;
      case 'river':
        return Icons.water_outlined;
      case 'crickets':
        return Icons.cruelty_free_outlined;
      case 'clock':
        return Icons.schedule;
      case 'keyboard':
        return Icons.keyboard;
      case 'wind':
        return Icons.air;
      case 'train_station':
        return Icons.train;
      case 'classroom':
        return Icons.school;
      case 'pebble_beach':
        return Icons.beach_access;
      case 'mall':
        return Icons.local_mall_outlined;
      case 'restaurant':
        return Icons.restaurant;
      case 'garden_birds':
        return Icons.park;
      case 'country_night':
        return Icons.nights_stay_outlined;
      case 'shallow_river':
        return Icons.water_outlined;
      case 'veranda_rain':
        return Icons.thunderstorm_outlined;
      case 'breeze_birds':
        return Icons.air;
      default:
        return Icons.music_off;
    }
  }

  void _showSoundPicker(
    BuildContext context,
    PomodoroProvider provider,
    String currentSound,
  ) {
    final customProvider = context.read<CustomFocusSoundProvider>();
    const volumeOptions = <double>[0.4, 0.6, 0.8, 1.0];
    showAppModalSheet(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: '选择白噪音',
        subtitle: '选择一段稳定循环的自然环境音',
        actions: [
          TextButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final imported = await customProvider.importAudio();
              if (!ctx.mounted) return;
              if (imported == null) return;
              final previewStarted = await provider.setWhiteNoiseSound(
                imported.id,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    previewStarted
                        ? '已导入 ${imported.label}'
                        : '已导入 ${imported.label}，但声音预览启动失败，请检查音频文件或系统音量',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('导入音频'),
          ),
        ],
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '点击声音会自动试听，也可以先点试听确认音量。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final value in volumeOptions)
                      ChoiceChip(
                        label: Text('${(value * 100).round()}%'),
                        selected: provider.config.focusSoundVolume == value,
                        onSelected: (_) async {
                          final messenger = ScaffoldMessenger.of(context);
                          final previewStarted = await provider
                              .setFocusSoundVolume(value);
                          if (!ctx.mounted) return;
                          setSheetState(() {});
                          if (!previewStarted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('专注音量预览启动失败，请先选择白噪音或检查系统音量'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 18),
              for (final option in FocusSoundCatalog.options)
                _SoundOptionTile(
                  title: option.label,
                  icon: _soundIcon(option.id),
                  selected: currentSound == option.id,
                  onPreview: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final previewStarted = await provider.setWhiteNoiseSound(
                      option.id,
                    );
                    if (!ctx.mounted) return;
                    if (!previewStarted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('专注声音试听启动失败，请检查系统音量或音频资源'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final previewStarted = await provider.setWhiteNoiseSound(
                      option.id,
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!previewStarted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('专注声音预览启动失败，请检查系统音量或音频资源'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              if (customProvider.sounds.isNotEmpty) ...[
                const Divider(height: 18),
                for (final sound in customProvider.sounds)
                  _SoundOptionTile(
                    title: sound.label,
                    subtitle: '自定义音频',
                    icon: _soundIcon(sound.id),
                    selected: currentSound == sound.id,
                    onPreview: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final previewStarted = await provider.setWhiteNoiseSound(
                        sound.id,
                      );
                      if (!ctx.mounted) return;
                      if (!previewStarted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('自定义专注声音试听启动失败，请检查音频文件或系统音量'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final previewStarted = await provider.setWhiteNoiseSound(
                        sound.id,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!previewStarted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('自定义专注声音预览启动失败，请检查音频文件或系统音量'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    onDelete: () async {
                      await customProvider.remove(sound.id);
                      if (provider.state.whiteNoiseSound == sound.id) {
                        await provider.setWhiteNoiseSound(
                          FocusSoundCatalog.none,
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showTaskPresetPicker(BuildContext context, PomodoroProvider provider) {
    final strings = context.read<ThemeProvider>().brand.strings;
    showAppModalSheet<void>(
      context: context,
      builder: (ctx) => Builder(
        builder: (sheetContext) {
          final todos =
              sheetContext.watch<TodoProvider?>()?.todos ?? const <TodoItem>[];
          final state = sheetContext.watch<PomodoroProvider>().state;
          return PomodoroTaskPicker(
            title: strings.focusTaskLinkLabel,
            todos: todos,
            selectedTodoId: state.todoId,
            selectedSubtaskId: state.subtaskId,
            hasSelection: state.taskName?.isNotEmpty == true,
            onSelected: (todo, child) {
              // The sheet watches account-local tasks, and selection never completes them.
              provider.setTaskTarget(
                todoId: todo.id,
                todoTitle: todo.title,
                taskName: child?.title ?? todo.title,
                subtaskId: child?.id,
              );
              Navigator.pop(ctx);
            },
            onPreset: (name) {
              provider.setTaskName(name);
              Navigator.pop(ctx);
            },
            onManual: () {
              Navigator.pop(ctx);
              _editTaskName(context, provider, state.taskName ?? '');
            },
            onClear: () {
              provider.setTaskName(null);
              Navigator.pop(ctx);
            },
          );
        },
      ),
    );
  }

  void _showDndSheet(BuildContext context) {
    showAppModalSheet(
      context: context,
      builder: (ctx) => Consumer<PomodoroProvider>(
        builder: (ctx, provider, _) {
          final cs = Theme.of(ctx).colorScheme;
          return AppModalSheet(
            title: '专注勿扰',
            subtitle: '开始专注时临时开启系统勿扰，暂停、结束或重置后恢复原状态',
            actions: [
              TextButton(
                onPressed: () async {
                  await provider.refreshFocusDndStatus();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('完成'),
              ),
              FilledButton.icon(
                onPressed: provider.focusDndStatus.supported
                    ? () => provider.openFocusDndSettings()
                    : null,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('去授权'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.do_not_disturb_on_outlined),
                  title: const Text('专注时自动开启勿扰'),
                  subtitle: Text(
                    provider.focusDndStatus.accessGranted
                        ? '已获得系统勿扰权限'
                        : '需要在系统设置中允许多仪控制勿扰模式',
                  ),
                  value: provider.config.autoEnableDnd,
                  onChanged: provider.setAutoEnableDnd,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    provider.focusDndStatus.supported
                        ? '未授权时不影响计时和白噪音播放；授权后仅在本轮专注进行中切换系统勿扰。'
                        : '当前平台不支持通过多仪控制系统勿扰。Android 6.0 及以上可用。',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FocusRoomTile extends StatelessWidget {
  final String roomName;
  final String subtitle;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  const _FocusRoomTile({
    required this.roomName,
    required this.subtitle,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          // 默认主题：控制行不再各自画卡片底/描边，交给外层 Apple 组面。
          decoration: usesApplePageLayout(context)
              ? null
              : BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 10,
              compact ? 6 : 8,
              compact ? 8 : 10,
              compact ? 6 : 8,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.groups_2_outlined,
                    color: color,
                    size: compact ? 15 : 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '专注自习室',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          height: 1.05,
                          color: cs.onSurface.withValues(alpha: 0.62),
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        roomName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: compact ? 12 : 13,
                          height: 1.08,
                          color: cs.onSurface,
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.56),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveFocusRoomTileViewModel {
  final String roomName;
  final String subtitle;
  final int colorValue;

  const _ActiveFocusRoomTileViewModel({
    required this.roomName,
    required this.subtitle,
    required this.colorValue,
  });

  @override
  bool operator ==(Object other) {
    return other is _ActiveFocusRoomTileViewModel &&
        other.roomName == roomName &&
        other.subtitle == subtitle &&
        other.colorValue == colorValue;
  }

  @override
  int get hashCode => Object.hash(roomName, subtitle, colorValue);
}

class _ActiveFocusRoomTile extends StatelessWidget {
  final String? focusRoomId;
  final bool compact;
  final VoidCallback onTap;

  const _ActiveFocusRoomTile({
    required this.focusRoomId,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Selector<FocusRoomProvider, _ActiveFocusRoomTileViewModel>(
      selector: (_, rooms) {
        final activeRoom = rooms.roomById(focusRoomId) ?? rooms.activeRoom;
        return _ActiveFocusRoomTileViewModel(
          roomName: activeRoom?.name ?? '未加入自习室',
          subtitle: activeRoom == null ? '选择本轮专注小组' : '本轮完成后计入排行榜',
          colorValue: activeRoom?.accentColor ?? fallbackColor.toARGB32(),
        );
      },
      builder: (context, state, _) => _FocusRoomTile(
        roomName: state.roomName,
        subtitle: state.subtitle,
        color: Color(state.colorValue),
        compact: compact,
        onTap: onTap,
      ),
    );
  }
}

class _WhiteNoiseControlTile extends StatelessWidget {
  final String sound;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  const _WhiteNoiseControlTile({
    required this.sound,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = context.select<CustomFocusSoundProvider, String>((custom) {
      return custom.isCustomSound(sound)
          ? custom.labelFor(sound)
          : FocusSoundCatalog.labelFor(sound);
    });
    return _FocusControlTile(
      icon: _PomodoroScreenState._soundIconForTile(sound),
      label: '白噪音',
      subtitle: label,
      color: color,
      compact: compact,
      onTap: onTap,
    );
  }
}

class _StrictFocusTile extends StatelessWidget {
  final bool enabled;
  final int todayCount;
  final bool compact;
  final Color color;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;

  const _StrictFocusTile({
    required this.enabled,
    required this.todayCount,
    required this.compact,
    required this.color,
    required this.onChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = enabled ? color : cs.onSurfaceVariant;
    final subtitle = enabled
        ? todayCount > 0
              ? '今日 $todayCount 次中断'
              : '中断会记入 ledger'
        : '手动开启';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          // 默认主题：控制行不再各自画卡片底/描边，交给外层 Apple 组面。
          decoration: usesApplePageLayout(context)
              ? null
              : BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 10,
              compact ? 5 : 7,
              compact ? 4 : 6,
              compact ? 5 : 7,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.lock_clock_outlined,
                    color: effectiveColor,
                    size: compact ? 15 : 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '严格专注',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          height: 1.05,
                          color: cs.onSurface.withValues(alpha: 0.62),
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: compact ? 12 : 13,
                          height: 1.08,
                          color: cs.onSurface,
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PenaltyListTile extends StatelessWidget {
  final PomodoroFocusPenalty penalty;

  const _PenaltyListTile(this.penalty);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time =
        '${penalty.occurredAt.month}/${penalty.occurredAt.day} '
        '${penalty.occurredAt.hour.toString().padLeft(2, '0')}:'
        '${penalty.occurredAt.minute.toString().padLeft(2, '0')}';
    final minutes = (penalty.affectedSeconds / 60).ceil().clamp(1, 1440);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(Icons.warning_amber_rounded, color: cs.error, size: 19),
      ),
      title: Text(penalty.reason.label),
      subtitle: Text(
        [
          time,
          '$minutes 分钟',
          if (penalty.taskName?.isNotEmpty == true) penalty.taskName!,
        ].join(' · '),
      ),
    );
  }
}

class _FocusRoomOptionTile extends StatelessWidget {
  final FocusRoom room;
  final bool joined;
  final bool selected;
  final VoidCallback onTap;

  const _FocusRoomOptionTile({
    required this.room,
    required this.joined,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(room.accentColor);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.groups_2_outlined, color: color, size: 20),
      ),
      title: Text(room.name),
      subtitle: Text(
        '${room.description} · 每周目标 ${room.weeklyTargetSeconds ~/ 60} 分钟',
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: cs.primary)
          : joined
          ? const Text('已加入')
          : const Text('加入'),
      onTap: onTap,
    );
  }
}

class _MaybePomodoroBackground extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const _MaybePomodoroBackground({required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return BrandBackground(child: child);
  }
}

class _PomodoroLiveTimer extends StatelessWidget {
  final PomodoroProvider provider;
  final Color color;
  final double ringSize;
  final bool tight;
  final String completedSuffix;
  final String timerLabel;
  final Color textColor;
  final String Function(int seconds) formatTime;

  const _PomodoroLiveTimer({
    required this.provider,
    required this.color,
    required this.ringSize,
    required this.tight,
    required this.completedSuffix,
    required this.timerLabel,
    required this.textColor,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: provider.timerTicks,
      builder: (context, _, _) {
        final state = provider.state;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: RepaintBoundary(
                child: PomodoroTimerRing(
                  progress: state.progress,
                  timeText: formatTime(state.remainingSeconds),
                  color: color,
                  size: ringSize,
                  countUp: state.isCountUp,
                ),
              ),
            ),
            SizedBox(height: tight ? 4 : 6),
            Center(
              child: Text(
                state.isCountUp
                    ? '自由计时 · ${state.completedSessions} $completedSuffix'
                    : '$timerLabel · ${state.completedSessions} $completedSuffix',
                style: TextStyle(color: textColor, fontSize: tight ? 12 : 13),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FocusRoomTab extends StatefulWidget {
  const _FocusRoomTab();

  @override
  State<_FocusRoomTab> createState() => _FocusRoomTabState();
}

class _FocusRoomTabState extends State<_FocusRoomTab>
    with AutomaticKeepAliveClientMixin<_FocusRoomTab> {
  String? _lastRefreshKey;
  bool _refreshScheduled = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rooms = context.read<FocusRoomProvider>();
    final pomodoroRevision = context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final focusRoomId = context.select<PomodoroProvider, String?>(
      (provider) => provider.state.focusRoomId,
    );
    final displayName = context.select<AuthProvider, String>((auth) {
      final username = auth.state.username?.trim();
      return username?.isNotEmpty == true ? username! : '我';
    });
    final joinedRefreshKey = context.select<FocusRoomProvider, String>((
      provider,
    ) {
      final ids = provider.joinedRoomIds.toList()..sort();
      return ids.join('|');
    });
    final activeRoomName = context.select<FocusRoomProvider, String?>(
      (provider) => provider.roomById(focusRoomId)?.name,
    );
    _scheduleRoomRefresh(
      context,
      rooms,
      pomodoroRevision,
      displayName,
      joinedRefreshKey,
    );

    return ListView(
      key: const PageStorageKey<String>('focus_room_tab_scroll'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      children: [
        _FocusSocialLeaderboardSection(
          displayName: displayName,
          onManageFriends: () =>
              _showFocusFriendSheet(context, context.read<FocusRoomProvider>()),
        ),
        const SizedBox(height: 12),
        _JoinedFocusRoomRankingSection(
          activeRoomName: activeRoomName,
          displayName: displayName,
          onAcceptInvite: () => _showAcceptFocusRoomInviteDialog(
            context,
            context.read<FocusRoomProvider>(),
            context.read<PomodoroProvider>(),
            displayName,
          ),
        ),
        const SizedBox(height: 12),
        _FocusRoomCatalogSection(
          displayName: displayName,
          onManageInvites: (room) => _showFocusRoomInviteSheet(
            context,
            context.read<FocusRoomProvider>(),
            room,
          ),
        ),
      ],
    );
  }

  void _scheduleRoomRefresh(
    BuildContext context,
    FocusRoomProvider rooms,
    int pomodoroRevision,
    String displayName,
    String joinedRefreshKey,
  ) {
    final refreshKey = [
      joinedRefreshKey,
      pomodoroRevision,
      displayName,
    ].join('::');
    if (_lastRefreshKey == refreshKey || _refreshScheduled) return;
    _lastRefreshKey = refreshKey;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      final roomProvider = context.read<FocusRoomProvider>();
      final pomodoroProvider = context.read<PomodoroProvider>();
      roomProvider.watchRealtimeRankings();
      unawaited(roomProvider.loadFocusFriendsAndRanking());
      unawaited(roomProvider.loadGlobalRanking());
      unawaited(
        roomProvider.syncRemoteRankings(
          pomodoroProvider.sessions,
          displayName: displayName,
          active: true,
        ),
      );
    });
  }

  Future<void> _showFocusRoomInviteSheet(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusRoom room,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await rooms.loadInvitesForRoom(room.id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    showAppModalSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer<FocusRoomProvider>(
        builder: (sheetContext, provider, _) {
          final invites = provider.invitesForRoom(room.id);
          return AppModalSheet(
            title: '邀请码管理',
            subtitle: room.name,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('完成'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (provider.remoteLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: provider.remoteLoading
                        ? null
                        : () => _showCreateFocusRoomInviteDialog(
                            context,
                            provider,
                            room,
                          ),
                    icon: const Icon(Icons.add_link_outlined),
                    label: const Text('新建邀请码'),
                  ),
                ),
                const SizedBox(height: 12),
                if (invites.isEmpty)
                  Text(
                    '还没有为这个自习室创建邀请码。',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        sheetContext,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  )
                else
                  ...invites.map(
                    (invite) => _FocusRoomInviteTile(
                      invite: invite,
                      meta: _focusRoomInviteMeta(invite),
                      active: _focusRoomInviteUsable(invite),
                      onCopy: () =>
                          _copyExistingFocusRoomInvite(context, invite),
                      onRevoke: invite.revoked
                          ? null
                          : () => _revokeFocusRoomInvite(
                              context,
                              provider,
                              room,
                              invite,
                            ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _createAndCopyFocusRoomInvite(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusRoom room,
    DateTime? expiresAt,
    int maxUses,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final invite = await rooms.createInviteForRoom(
        room.id,
        expiresAt: expiresAt,
        maxUses: maxUses,
      );
      await Clipboard.setData(ClipboardData(text: invite.code));
      messenger.showSnackBar(
        SnackBar(
          content: Text('已复制邀请码 ${invite.code}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showCreateFocusRoomInviteDialog(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusRoom room,
  ) {
    var expiryDays = 0;
    var maxUses = 0;
    showAppModalSheet<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AppModalSheet(
          key: const ValueKey('focus_room_invite_create_sheet'),
          title: '新建邀请码',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final expiresAt = expiryDays <= 0
                    ? null
                    : DateTime.now().add(Duration(days: expiryDays));
                await _createAndCopyFocusRoomInvite(
                  context,
                  rooms,
                  room,
                  expiresAt,
                  maxUses,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.add_link_outlined),
              label: const Text('创建并复制'),
            ),
          ],
          child: AppFormFieldTheme(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppDropdownField<int>(
                  initialValue: expiryDays,
                  decoration: const InputDecoration(
                    labelText: '有效期',
                    prefixIcon: Icon(Icons.event_available_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('不过期')),
                    DropdownMenuItem(value: 1, child: Text('1 天')),
                    DropdownMenuItem(value: 7, child: Text('7 天')),
                    DropdownMenuItem(value: 30, child: Text('30 天')),
                  ],
                  onChanged: (value) => setState(() => expiryDays = value ?? 0),
                ),
                const SizedBox(height: 10),
                AppDropdownField<int>(
                  initialValue: maxUses,
                  decoration: const InputDecoration(
                    labelText: '使用次数',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('不限次数')),
                    DropdownMenuItem(value: 1, child: Text('1 次')),
                    DropdownMenuItem(value: 5, child: Text('5 次')),
                    DropdownMenuItem(value: 10, child: Text('10 次')),
                    DropdownMenuItem(value: 50, child: Text('50 次')),
                  ],
                  onChanged: (value) => setState(() => maxUses = value ?? 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyExistingFocusRoomInvite(
    BuildContext context,
    FocusRoomInvite invite,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: invite.code));
    messenger.showSnackBar(
      SnackBar(
        content: Text('已复制邀请码 ${invite.code}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _revokeFocusRoomInvite(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusRoom room,
    FocusRoomInvite invite,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await rooms.revokeInviteForRoom(room.id, invite.id);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('已撤销邀请码'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _focusRoomInviteMeta(FocusRoomInvite invite) {
    final status = invite.revoked
        ? '已撤销'
        : _focusRoomInviteDepleted(invite)
        ? '已用尽'
        : invite.expiresAt == null
        ? '永久有效'
        : invite.expiresAt!.isBefore(DateTime.now())
        ? '已过期'
        : '有效至 ${_formatShortDateTime(invite.expiresAt!)}';
    final usage = invite.maxUses <= 0
        ? '不限次数'
        : '${invite.usedCount}/${invite.maxUses} 次';
    final lastUsed = invite.lastUsedAt == null
        ? null
        : '最近 ${_formatShortDateTime(invite.lastUsedAt!)}';
    final created = invite.createdAt == null
        ? null
        : '创建 ${_formatShortDateTime(invite.createdAt!)}';
    return [status, usage, ?lastUsed, ?created].join(' · ');
  }

  bool _focusRoomInviteUsable(FocusRoomInvite invite) {
    if (invite.revoked) return false;
    if (_focusRoomInviteDepleted(invite)) return false;
    final expiresAt = invite.expiresAt;
    return expiresAt == null || expiresAt.isAfter(DateTime.now());
  }

  bool _focusRoomInviteDepleted(FocusRoomInvite invite) {
    return invite.maxUses > 0 && invite.usedCount >= invite.maxUses;
  }

  String _formatShortDateTime(DateTime value) {
    final local = AppClock.toLocal(value);
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _showAcceptFocusRoomInviteDialog(
    BuildContext context,
    FocusRoomProvider rooms,
    PomodoroProvider pomodoro,
    String displayName,
  ) {
    final codeCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('输入邀请码'),
        shiftForKeyboard: true,
        content: _PomodoroDialogBody(
          child: TextField(
            controller: codeCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '自习室邀请码',
              prefixIcon: Icon(Icons.key_outlined),
            ),
            onSubmitted: (_) => _acceptFocusRoomInvite(
              context,
              ctx,
              rooms,
              pomodoro,
              codeCtrl.text,
              displayName,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => _acceptFocusRoomInvite(
              context,
              ctx,
              rooms,
              pomodoro,
              codeCtrl.text,
              displayName,
            ),
            icon: const Icon(Icons.login_outlined),
            label: const Text('加入自习室'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptFocusRoomInvite(
    BuildContext context,
    BuildContext dialogContext,
    FocusRoomProvider rooms,
    PomodoroProvider pomodoro,
    String code,
    String displayName,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final room = await rooms.acceptInviteCode(code, displayName: displayName);
      await pomodoro.setFocusRoomId(room.id);
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已加入自习室：${room.name}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showFocusFriendSheet(
    BuildContext context,
    FocusRoomProvider rooms,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await rooms.loadFocusFriendsAndRanking(force: true);
    if (!context.mounted) return;
    showAppModalSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer<FocusRoomProvider>(
        builder: (sheetContext, provider, _) {
          final friends = provider.focusFriends;
          final incoming = provider.incomingFriendRequests;
          final outgoing = provider.outgoingFriendRequests;
          final hasRows =
              friends.isNotEmpty || incoming.isNotEmpty || outgoing.isNotEmpty;
          return AppModalSheet(
            title: '专注好友',
            subtitle: provider.remoteFriendRankingActive
                ? '服务端好友关系已用于好友专注榜'
                : '登录后同步好友关系和在线状态',
            actions: [
              IconButton(
                tooltip: '刷新好友',
                onPressed: provider.friendLoading
                    ? null
                    : () => provider.loadFocusFriendsAndRanking(force: true),
                icon: provider.friendLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('完成'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: provider.friendLoading
                      ? null
                      : () => _showAddFocusFriendDialog(context, provider),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('发送好友申请'),
                ),
                const SizedBox(height: 12),
                if (provider.friendLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (!hasRows)
                  Text(
                    '还没有专注好友或待处理申请。',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        sheetContext,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  )
                else ...[
                  if (incoming.isNotEmpty) ...[
                    const _FocusFriendSheetLabel('收到的申请'),
                    ...incoming.map(
                      (request) => _FocusFriendRequestTile(
                        request: request,
                        onAccept: () => _acceptFocusFriendRequest(
                          context,
                          provider,
                          request,
                        ),
                        onReject: () => _rejectFocusFriendRequest(
                          context,
                          provider,
                          request,
                        ),
                      ),
                    ),
                  ],
                  if (outgoing.isNotEmpty) ...[
                    const _FocusFriendSheetLabel('已发出的申请'),
                    ...outgoing.map(
                      (request) => _FocusFriendRequestTile(
                        request: request,
                        onCancel: () => _cancelFocusFriendRequest(
                          context,
                          provider,
                          request,
                        ),
                      ),
                    ),
                  ],
                  if (friends.isNotEmpty) const _FocusFriendSheetLabel('已有好友'),
                  ...friends.map(
                    (friend) => _FocusFriendTile(
                      friend: friend,
                      onRemove: () =>
                          _removeFocusFriend(context, provider, friend),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ).catchError((Object e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void _showAddFocusFriendDialog(
    BuildContext context,
    FocusRoomProvider rooms,
  ) {
    final usernameCtrl = TextEditingController();
    showAppModalSheet<void>(
      context: context,
      builder: (dialogContext) => AppModalSheet(
        key: const ValueKey('focus_friend_create_sheet'),
        title: '发送好友申请',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => _addFocusFriend(
              context,
              dialogContext,
              rooms,
              usernameCtrl.text,
            ),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('发送申请'),
          ),
        ],
        child: AppFormFieldTheme(
          child: TextField(
            controller: usernameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '好友用户名',
              prefixIcon: Icon(Icons.alternate_email_outlined),
            ),
            onSubmitted: (_) => _addFocusFriend(
              context,
              dialogContext,
              rooms,
              usernameCtrl.text,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addFocusFriend(
    BuildContext context,
    BuildContext dialogContext,
    FocusRoomProvider rooms,
    String username,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final friend = await rooms.addFocusFriend(username);
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      final accepted = friend.status == 'accepted';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? '已添加专注好友：${friend.username}'
                : '已发送好友申请：${friend.username}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _acceptFocusFriendRequest(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusFriendRequest request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final friend = await rooms.acceptFocusFriendRequest(request.userId);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已同意 ${friend.username} 的好友申请'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _rejectFocusFriendRequest(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusFriendRequest request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await rooms.rejectFocusFriendRequest(request.userId);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已拒绝 ${request.username} 的好友申请'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancelFocusFriendRequest(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusFriendRequest request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await rooms.cancelFocusFriendRequest(request.userId);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已取消发送给 ${request.username} 的好友申请'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeFocusFriend(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusFriend friend,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await rooms.removeFocusFriend(friend.userId);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已移除 ${friend.username}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _FocusSocialLeaderboardSection extends StatelessWidget {
  final String displayName;
  final VoidCallback onManageFriends;

  const _FocusSocialLeaderboardSection({
    required this.displayName,
    required this.onManageFriends,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = context.read<PomodoroProvider>().sessions;
    return Selector<FocusRoomProvider, _FocusSocialLeaderboardViewModel>(
      selector: (_, rooms) => _FocusSocialLeaderboardViewModel(
        rankings: [
          rooms.socialRankingFor(
            FocusLeaderboardScope.friends,
            sessions,
            currentUserName: displayName,
          ),
          rooms.socialRankingFor(
            FocusLeaderboardScope.global,
            sessions,
            currentUserName: displayName,
          ),
        ],
        friendLoading: rooms.friendLoading,
        globalLoading: rooms.globalLoading,
      ),
      builder: (context, state, _) => AppSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionHeader(
              title: '好友与全局排行榜',
              subtitle: '按本周有效专注时长排名，异常时长会自动封顶',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            ...state.rankings.map(
              (ranking) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FocusSocialRankingCard(
                  ranking: ranking,
                  loading: ranking.scope == FocusLeaderboardScope.friends
                      ? state.friendLoading
                      : state.globalLoading,
                  onRefresh: ranking.scope == FocusLeaderboardScope.friends
                      ? () => context
                            .read<FocusRoomProvider>()
                            .loadFocusFriendsAndRanking(force: true)
                      : () => context
                            .read<FocusRoomProvider>()
                            .loadGlobalRanking(force: true),
                  onManage: ranking.scope == FocusLeaderboardScope.friends
                      ? onManageFriends
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusSocialLeaderboardViewModel {
  final List<FocusSocialRanking> rankings;
  final bool friendLoading;
  final bool globalLoading;

  const _FocusSocialLeaderboardViewModel({
    required this.rankings,
    required this.friendLoading,
    required this.globalLoading,
  });

  @override
  bool operator ==(Object other) {
    return other is _FocusSocialLeaderboardViewModel &&
        other.friendLoading == friendLoading &&
        other.globalLoading == globalLoading &&
        _focusSocialRankingsSignature(other.rankings) ==
            _focusSocialRankingsSignature(rankings);
  }

  @override
  int get hashCode => Object.hash(
    friendLoading,
    globalLoading,
    _focusSocialRankingsSignature(rankings),
  );
}

class _JoinedFocusRoomRankingSection extends StatelessWidget {
  final String? activeRoomName;
  final String displayName;
  final VoidCallback onAcceptInvite;

  const _JoinedFocusRoomRankingSection({
    required this.activeRoomName,
    required this.displayName,
    required this.onAcceptInvite,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = context.read<PomodoroProvider>().sessions;
    return Selector<FocusRoomProvider, _JoinedFocusRoomRankingViewModel>(
      selector: (_, rooms) => _JoinedFocusRoomRankingViewModel(
        rankings: rooms.joinedRooms
            .map(
              (room) => rooms.effectiveRankingFor(
                room.id,
                sessions,
                currentUserName: displayName,
              ),
            )
            .toList(),
        loading: rooms.remoteLoading,
        realtimeActive: rooms.realtimeRankingsActive,
        fallbackToLocal: rooms.fallbackToLocal || rooms.lastRemoteError != null,
      ),
      builder: (context, state, _) => AppSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              title: '专注自习室',
              subtitle: activeRoomName == null
                  ? '选择一个房间后，本轮专注会计入本周排行榜'
                  : '当前本轮计入：$activeRoomName',
              padding: EdgeInsets.zero,
              actionLabel: '输入邀请码',
              actionIcon: Icons.key_outlined,
              onAction: onAcceptInvite,
            ),
            const SizedBox(height: 12),
            if (state.loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (state.realtimeActive && !state.fallbackToLocal)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppStatusBadge(
                  label: '实时房间',
                  color: Colors.green,
                  icon: Icons.bolt_outlined,
                ),
              ),
            if (state.fallbackToLocal)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppStatusBadge(
                  label: focusRoomRankingUnavailableMessage,
                  color: Theme.of(context).colorScheme.outline,
                  icon: Icons.cloud_off_outlined,
                ),
              ),
            if (state.rankings.isEmpty)
              const Text('还没有加入自习室')
            else
              ...state.rankings.map(
                (ranking) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FocusRoomRankingCard(ranking: ranking),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JoinedFocusRoomRankingViewModel {
  final List<FocusRoomRanking> rankings;
  final bool loading;
  final bool realtimeActive;
  final bool fallbackToLocal;

  const _JoinedFocusRoomRankingViewModel({
    required this.rankings,
    required this.loading,
    required this.realtimeActive,
    required this.fallbackToLocal,
  });

  @override
  bool operator ==(Object other) {
    return other is _JoinedFocusRoomRankingViewModel &&
        other.loading == loading &&
        other.realtimeActive == realtimeActive &&
        other.fallbackToLocal == fallbackToLocal &&
        _focusRoomRankingsSignature(other.rankings) ==
            _focusRoomRankingsSignature(rankings);
  }

  @override
  int get hashCode => Object.hash(
    loading,
    realtimeActive,
    fallbackToLocal,
    _focusRoomRankingsSignature(rankings),
  );
}

class _FocusRoomCatalogSection extends StatelessWidget {
  final String displayName;
  final void Function(FocusRoom room) onManageInvites;

  const _FocusRoomCatalogSection({
    required this.displayName,
    required this.onManageInvites,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<FocusRoomProvider, _FocusRoomCatalogViewModel>(
      selector: (_, rooms) => _FocusRoomCatalogViewModel(
        rooms: rooms.rooms,
        joinedRoomIds: rooms.joinedRoomIds,
      ),
      builder: (context, state, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(
            title: '可加入房间',
            subtitle: '点击加入；已加入房间可复制邀请码',
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          ),
          ...state.rooms.map((room) {
            final joined = state.joinedRoomIds.contains(room.id);
            return AppSurfaceCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              onTap: () async {
                final pomodoroProvider = context.read<PomodoroProvider>();
                final focusRoomProvider = context.read<FocusRoomProvider>();
                await focusRoomProvider.joinRoom(room.id);
                await pomodoroProvider.setFocusRoomId(room.id);
                if (!context.mounted) return;
                await focusRoomProvider.syncRemoteRankings(
                  pomodoroProvider.sessions,
                  displayName: displayName,
                  active: true,
                  force: true,
                );
              },
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Color(room.accentColor).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.groups_2_outlined,
                      color: Color(room.accentColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: DesignTokens.fontWeightStrong,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          room.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.62),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (joined) ...[
                    AppStatusBadge(
                      label: '已加入',
                      color: Theme.of(context).colorScheme.primary,
                      icon: Icons.check_circle_outline,
                    ),
                    IconButton(
                      tooltip: '管理邀请码',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onManageInvites(room),
                      icon: const Icon(Icons.key_outlined),
                    ),
                  ] else
                    Text(
                      '加入',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _FocusRoomCatalogViewModel {
  final List<FocusRoom> rooms;
  final Set<String> joinedRoomIds;

  const _FocusRoomCatalogViewModel({
    required this.rooms,
    required this.joinedRoomIds,
  });

  @override
  bool operator ==(Object other) {
    return other is _FocusRoomCatalogViewModel &&
        _focusRoomsSignature(other.rooms) == _focusRoomsSignature(rooms) &&
        _stringSetSignature(other.joinedRoomIds) ==
            _stringSetSignature(joinedRoomIds);
  }

  @override
  int get hashCode => Object.hash(
    _focusRoomsSignature(rooms),
    _stringSetSignature(joinedRoomIds),
  );
}

String _focusSocialRankingsSignature(List<FocusSocialRanking> rankings) {
  return rankings
      .map((ranking) {
        return [
          ranking.scope.name,
          ranking.remote,
          ranking.onlineCount,
          ranking.suspiciousEntryCount,
          ranking.updatedAt?.microsecondsSinceEpoch ?? 0,
          _focusRankingEntriesSignature(ranking.entries),
        ].join(',');
      })
      .join('|');
}

String _focusRoomRankingsSignature(List<FocusRoomRanking> rankings) {
  return rankings
      .map((ranking) {
        return [
          ranking.room.id,
          ranking.room.name,
          ranking.room.accentColor,
          ranking.userWeeklySeconds,
          ranking.userSessionCount,
          ranking.remote,
          ranking.onlineCount,
          ranking.updatedAt?.microsecondsSinceEpoch ?? 0,
          _focusRankingEntriesSignature(ranking.entries),
        ].join(',');
      })
      .join('|');
}

String _focusRankingEntriesSignature(List<FocusRoomRankingEntry> entries) {
  return entries
      .map((entry) {
        return [
          entry.id,
          entry.name,
          entry.rank,
          entry.weeklySeconds,
          entry.rawWeeklySeconds,
          entry.sessionCount,
          entry.online,
          entry.active,
          entry.flagged,
          entry.flagReason ?? '',
          entry.lastSeenAt?.microsecondsSinceEpoch ?? 0,
        ].join(':');
      })
      .join(';');
}

String _focusRoomsSignature(List<FocusRoom> rooms) {
  return rooms
      .map((room) {
        return [
          room.id,
          room.name,
          room.description,
          room.weeklyTargetSeconds,
          room.accentColor,
          room.createdAt.microsecondsSinceEpoch,
        ].join(':');
      })
      .join('|');
}

String _stringSetSignature(Set<String> values) {
  final sorted = values.toList()..sort();
  return sorted.join('|');
}

class _FocusFriendSheetLabel extends StatelessWidget {
  final String label;

  const _FocusFriendSheetLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: DesignTokens.fontWeightStrong,
        ),
      ),
    );
  }
}

class _FocusFriendRequestTile extends StatelessWidget {
  final FocusFriendRequest request;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  const _FocusFriendRequestTile({
    required this.request,
    this.onAccept,
    this.onReject,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = request.incoming ? cs.primary : cs.tertiary;
    final meta = request.incoming ? '等待你处理' : '等待对方同意';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.person_add_alt_1_outlined,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  request.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (request.incoming) ...[
            IconButton(
              tooltip: '同意好友申请',
              visualDensity: VisualDensity.compact,
              onPressed: onAccept,
              icon: const Icon(Icons.check_circle_outline),
            ),
            IconButton(
              tooltip: '拒绝好友申请',
              visualDensity: VisualDensity.compact,
              onPressed: onReject,
              icon: const Icon(Icons.cancel_outlined),
            ),
          ] else
            IconButton(
              tooltip: '取消好友申请',
              visualDensity: VisualDensity.compact,
              onPressed: onCancel,
              icon: const Icon(Icons.undo_outlined),
            ),
        ],
      ),
    );
  }
}

class _FocusFriendTile extends StatelessWidget {
  final FocusFriend friend;
  final VoidCallback onRemove;

  const _FocusFriendTile({required this.friend, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = friend.online ? Colors.green : cs.outline;
    final lastActive = friend.lastActiveAt == null
        ? '暂无活跃记录'
        : '最近活跃 ${_formatFriendTime(friend.lastActiveAt!)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.person_outline, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  friend.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  friend.online ? '在线 · $lastActive' : '离线 · $lastActive',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '移除好友',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.person_remove_outlined),
          ),
        ],
      ),
    );
  }

  String _formatFriendTime(DateTime value) {
    final local = AppClock.toLocal(value);
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _FocusRoomInviteTile extends StatelessWidget {
  final FocusRoomInvite invite;
  final String meta;
  final bool active;
  final VoidCallback onCopy;
  final VoidCallback? onRevoke;

  const _FocusRoomInviteTile({
    required this.invite,
    required this.meta,
    required this.active,
    required this.onCopy,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.outline;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.key_outlined, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  invite.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: DesignTokens.fontWeightStrong,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '复制邀请码',
            visualDensity: VisualDensity.compact,
            onPressed: active ? onCopy : null,
            icon: const Icon(Icons.content_copy_outlined),
          ),
          IconButton(
            tooltip: '撤销邀请码',
            visualDensity: VisualDensity.compact,
            onPressed: onRevoke,
            icon: const Icon(Icons.link_off_outlined),
          ),
        ],
      ),
    );
  }
}

class _FocusSocialRankingCard extends StatelessWidget {
  final FocusSocialRanking ranking;
  final bool loading;
  final VoidCallback? onRefresh;
  final VoidCallback? onManage;

  const _FocusSocialRankingCard({
    required this.ranking,
    this.loading = false,
    this.onRefresh,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = ranking.scope == FocusLeaderboardScope.friends
        ? Colors.indigo
        : Colors.deepOrange;
    final remoteBadgeLabel = ranking.scope == FocusLeaderboardScope.friends
        ? '服务端好友'
        : '服务端全站';
    final refreshTooltip = ranking.scope == FocusLeaderboardScope.friends
        ? '刷新好友榜'
        : '刷新全局榜';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ranking.scope == FocusLeaderboardScope.friends
                    ? Icons.people_alt_outlined
                    : Icons.public_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ranking.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  tooltip: refreshTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined, size: 18),
                ),
              if (onManage != null)
                IconButton(
                  tooltip: '管理专注好友',
                  visualDensity: VisualDensity.compact,
                  onPressed: onManage,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                ),
              if (ranking.suspiciousEntryCount > 0)
                AppStatusBadge(
                  label: '${ranking.suspiciousEntryCount} 条已校正',
                  color: Colors.orange,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ranking.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          if (ranking.remote)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  AppStatusBadge(
                    label: remoteBadgeLabel,
                    color: Colors.green,
                    icon: Icons.cloud_done_outlined,
                  ),
                  AppStatusBadge(
                    label: '在线 ${ranking.onlineCount}',
                    color: color,
                    icon: Icons.radio_button_checked,
                  ),
                ],
              ),
            ),
          ...ranking.entries
              .take(5)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _FocusRankingEntryRow(entry: entry, color: color),
                ),
              ),
        ],
      ),
    );
  }
}

class _FocusRoomRankingCard extends StatelessWidget {
  final FocusRoomRanking ranking;

  const _FocusRoomRankingCard({required this.ranking});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(ranking.room.accentColor);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ranking.room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${ranking.userWeeklyMinutes} / ${ranking.room.weeklyTargetSeconds ~/ 60} 分钟',
                style: TextStyle(
                  color: color,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AppStatusBadge(
                label: ranking.remote ? '服务端排行' : '本地排行',
                color: ranking.remote ? Colors.green : cs.outline,
                icon: ranking.remote
                    ? Icons.cloud_done_outlined
                    : Icons.storage_outlined,
              ),
              if (ranking.remote)
                AppStatusBadge(
                  label: '在线 ${ranking.onlineCount}',
                  color: color,
                  icon: Icons.radio_button_checked,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: (ranking.targetProgressPercent / 100).clamp(0.0, 1.0),
              backgroundColor: color.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          ...ranking.entries
              .take(4)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _FocusRankingEntryRow(entry: entry, color: color),
                ),
              ),
        ],
      ),
    );
  }
}

class _FocusRankingEntryRow extends StatelessWidget {
  final FocusRoomRankingEntry entry;
  final Color color;

  const _FocusRankingEntryRow({required this.entry, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.62);
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '#${entry.rank}',
            style: TextStyle(
              color: entry.isCurrentUser ? color : cs.onSurfaceVariant,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: entry.isCurrentUser ? color : cs.onSurface,
                    fontWeight: entry.isCurrentUser
                        ? DesignTokens.fontWeightStrong
                        : DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
              if (entry.online) ...[
                const SizedBox(width: 6),
                Icon(Icons.circle, size: 8, color: Colors.green.shade600),
              ],
              if (entry.flagged) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: entry.flagReason ?? '异常时长已校正',
                  child: Icon(
                    Icons.verified_user_outlined,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${entry.weeklyMinutes} 分钟 · ${entry.sessionCount} 次',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

class _FocusDndTile extends StatelessWidget {
  final bool enabled;
  final bool active;
  final bool accessGranted;
  final bool supported;
  final bool compact;
  final Color color;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;

  const _FocusDndTile({
    required this.enabled,
    required this.active,
    required this.accessGranted,
    required this.supported,
    required this.compact,
    required this.color,
    required this.onChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = !supported
        ? '当前平台不可用'
        : active
        ? '系统勿扰已开启'
        : enabled && accessGranted
        ? '开始专注后开启'
        : enabled
        ? '需要系统授权'
        : '手动开启';
    final effectiveColor = enabled ? color : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          // 默认主题：控制行不再各自画卡片底/描边，交给外层 Apple 组面。
          decoration: usesApplePageLayout(context)
              ? null
              : BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 10,
              compact ? 5 : 7,
              compact ? 4 : 6,
              compact ? 5 : 7,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.do_not_disturb_on_outlined,
                    color: effectiveColor,
                    size: compact ? 15 : 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '专注勿扰',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          height: 1.05,
                          color: cs.onSurface.withValues(alpha: 0.62),
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: compact ? 12 : 13,
                          height: 1.08,
                          color: cs.onSurface,
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  onChanged: supported ? onChanged : null,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusControlTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  const _FocusControlTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          // 默认主题：控制行不再各自画卡片底/描边，交给外层 Apple 组面。
          decoration: usesApplePageLayout(context)
              ? null
              : BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.36),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 10,
              compact ? 7 : 9,
              compact ? 8 : 10,
              compact ? 7 : 9,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: compact ? 15 : 17),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          height: 1.05,
                          color: cs.onSurface.withValues(alpha: 0.62),
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: compact ? 12 : 13,
                          height: 1.08,
                          color: cs.onSurface,
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundOptionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onPreview;
  final VoidCallback? onDelete;

  const _SoundOptionTile({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onPreview,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: cs.primary, size: 20),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPreview != null)
            IconButton(
              tooltip: '试听',
              onPressed: onPreview,
              icon: const Icon(Icons.volume_up_outlined),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: '删除自定义音频',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          if (selected) Icon(Icons.check_rounded, color: cs.primary),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _HistoryTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final provider = context.read<PomodoroProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final sessions =
        provider.sessions.where((s) => s.type == PomodoroType.focus).toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));

    if (sessions.isEmpty) {
      return EmptyState(icon: Icons.history, message: s.focusEmpty);
    }

    // Weekly chart data - last 7 days
    final now = AppClock.today();
    final chartData = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final start = AppClock.date(d.year, d.month, d.day);
      final end = AppClock.date(d.year, d.month, d.day + 1);
      return provider.sessions
              .where(
                (s) =>
                    s.type == PomodoroType.focus &&
                    !s.startTime.isBefore(start) &&
                    s.startTime.isBefore(end),
              )
              .fold(0, (sum, s) => sum + s.durationSeconds) ~/
          60;
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        AppSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionHeader(
                title: '最近 7 天',
                subtitle: '按专注分钟统计',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: '今日',
                      value: '${provider.sessionCountToday} 次',
                      icon: Icons.today_outlined,
                      color: const Color(0xFFE53935),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MiniStat(
                      label: '本周',
                      value: '${chartData.reduce((a, b) => a + b)} 分钟',
                      icon: Icons.view_week_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MiniStat(
                      label: '总计',
                      value: '${provider.totalFocusMinutes} 分钟',
                      icon: Icons.schedule,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (chartData.reduce((a, b) => a > b ? a : b) + 10)
                          .toDouble(),
                      barGroups: List.generate(
                        7,
                        (i) => BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: chartData[i].toDouble(),
                              color: const Color(0xFFE53935),
                              width: 22,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}m',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final labels = [
                                '一',
                                '二',
                                '三',
                                '四',
                                '五',
                                '六',
                                '日',
                              ];
                              final idx =
                                  (now.weekday - (6 - v.toInt()) + 7) % 7;
                              return Text(
                                labels[idx],
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppSectionHeader(
          title: '会话记录',
          subtitle: '${sessions.length} 次专注',
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _showFocusReport(context, FocusReportPeriod.week),
                  icon: const Icon(Icons.summarize_outlined, size: 18),
                  label: const Text('复制本周专注报告'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _showFocusReport(context, FocusReportPeriod.month),
                  icon: const Icon(Icons.ios_share_outlined, size: 18),
                  label: const Text('复制本月报告'),
                ),
              ),
            ],
          ),
        ),
        // Group sessions by date
        ..._groupedSessions(sessions).entries.map(
          (e) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  e.key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: DesignTokens.fontWeightStrong,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ),
              ...e.value.map(
                (s) => PomodoroSessionCard(
                  session: s,
                  onEdit: () => showPomodoroSessionEditor(context, s),
                  onDelete: () => provider.deleteSession(s.id),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, List<PomodoroSession>> _groupedSessions(
    List<PomodoroSession> sessions,
  ) {
    final map = <String, List<PomodoroSession>>{};
    for (final s in sessions) {
      final local = AppClock.toLocal(s.startTime);
      final key = '${local.year}-${local.month}月${local.day}日';
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

  Future<void> _showFocusReport(
    BuildContext context,
    FocusReportPeriod period,
  ) async {
    final provider = context.read<PomodoroProvider>();
    final report = FocusReportBuilder.build(
      sessions: provider.sessions,
      penalties: provider.penalties,
      period: period,
    );
    final markdown = report.toMarkdown();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: Text(report.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
          child: SingleChildScrollView(
            child: SelectableText(
              markdown,
              style: const TextStyle(height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: markdown));
              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('专注报告 Markdown 已复制'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制 Markdown'),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: DesignTokens.fontWeightStrong,
            fontSize: 18,
            color: cs.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.62),
            fontSize: 12,
            fontWeight: DesignTokens.fontWeightStrong,
          ),
        ),
      ],
    );
  }
}
