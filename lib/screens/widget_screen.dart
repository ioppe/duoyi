import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/design_tokens.dart';
import '../core/web_target.dart';
import '../core/i18n.dart';
import '../providers/theme_provider.dart';
import '../services/android_widget_manager.dart';
import '../services/home_widget_service.dart';
import '../widgets/surface_components.dart';
import 'calendar_screen.dart';

class WidgetScreen extends StatefulWidget {
  final bool asSettings;

  const WidgetScreen({super.key, this.asSettings = false});

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen>
    with WidgetsBindingObserver {
  static const _displayModeKey = 'duoyi_widget_display_mode';
  WidgetDisplayMode _displayMode = WidgetDisplayMode.standard;
  AndroidWidgetPinResult? _pinSupport;
  bool _checkingPinSupport = true;
  bool _canOpenWidgetSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDisplayMode();
    _loadPinSupport();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPinSupport();
    }
  }

  Future<void> _loadDisplayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_displayModeKey);
    if (!mounted) return;
    setState(() {
      _displayMode = WidgetDisplayMode.fromId(value);
    });
  }

  Future<void> _loadPinSupport() async {
    final support = await AndroidWidgetManager.checkPinSupport();
    final canOpenSettings = await AndroidWidgetManager.canOpenWidgetSettings();
    if (!mounted) return;
    setState(() {
      _pinSupport = support;
      _checkingPinSupport = false;
      _canOpenWidgetSettings = canOpenSettings;
    });
  }

  Future<void> _setDisplayMode(WidgetDisplayMode mode) async {
    setState(() => _displayMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayModeKey, mode.id);
    if (WebTarget.isWebBuild) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(I18n.tr('widget.style.saved'))));
      return;
    }
    final homeWidgetSynced = await HomeWidgetService.setDisplayMode(mode.id);
    final appliedCount =
        await AndroidWidgetManager.applyDisplayModeToExistingWidgets(
          mode.androidStyle,
        );
    if (!mounted) return;
    final nativeSynced = appliedCount != null;
    final message = !nativeSynced || (!homeWidgetSynced && appliedCount != 0)
        ? '应用内样式已保存，但桌面小组件同步失败；请稍后重试或重新添加小组件'
        : appliedCount > 0
        ? '小组件样式已设为${mode.label}，已同步 $appliedCount 个桌面实例；桌面格子大小仍由启动器控制'
        : '小组件样式已设为${mode.label}，当前未检测到已添加的桌面实例；新添加时会请求 ${mode.launcherRequestLabel}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openWidgetSettings() async {
    final opened = await AndroidWidgetManager.openWidgetSettings();
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开应用设置，请手动进入系统设置检查多仪权限')));
    }
  }

  void _setPinSupport(AndroidWidgetPinResult support) {
    if (!mounted) return;
    setState(() {
      _pinSupport = support;
      _checkingPinSupport = false;
    });
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
        title: Text(
          widget.asSettings
              ? I18n.tr('mine.tile.widget_settings')
              : I18n.tr('nav.widget'),
        ),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: WebTarget.isDesktopWebBuild && !widget.asSettings
            ? const _DesktopWebWidgetFallback()
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                children: [
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(16),
                    color: cs.surface.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.teal.withValues(alpha: 0.14),
                          child: const Icon(
                            Icons.widgets_outlined,
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '桌面小组件预览',
                            style: appSecondaryMenuItemTextStyle(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _WidgetDisplayModePanel(
                    value: _displayMode,
                    onChanged: _setDisplayMode,
                  ),
                  const SizedBox(height: 12),
                  _WidgetPinSupportBanner(
                    result: _pinSupport,
                    checking: _checkingPinSupport,
                    canOpenSettings: _canOpenWidgetSettings,
                    onRefresh: _loadPinSupport,
                    onOpenSettings: _openWidgetSettings,
                  ),
                  const SizedBox(height: 12),
                  _WidgetCatalogTile(
                    icon: Icons.checklist_rtl_outlined,
                    title: '今日待办',
                    subtitle: I18n.tr('widget.todo_preview_description'),
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.todo(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.todo,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 16),
                  _WidgetCatalogTile(
                    icon: Icons.timer_outlined,
                    title: '专注',
                    subtitle: I18n.tr('widget.focus_preview_description'),
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.focus(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.focus,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 16),
                  const _WidgetCatalogTile(
                    icon: Icons.self_improvement_outlined,
                    title: '习惯',
                    subtitle: '今日习惯进度、待打卡习惯和连续记录',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.habit(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.habit,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 16),
                  const _WidgetCatalogTile(
                    icon: Icons.calendar_month_outlined,
                    title: '月历',
                    subtitle: '显示本月日期和今日标记',
                    color: Colors.indigo,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.calendar(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.calendar,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 16),
                  const _WidgetCatalogTile(
                    icon: Icons.event_note_outlined,
                    title: '今日日程',
                    subtitle: '展示今天的日程和提醒时间',
                    color: Colors.cyan,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.schedule(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.schedule,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 16),
                  const _WidgetCatalogTile(
                    icon: Icons.flag_outlined,
                    title: '目标',
                    subtitle: '展示进行中目标和进度',
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.goal(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.goal,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 16),
                  const _WidgetCatalogTile(
                    icon: Icons.school_outlined,
                    title: '课程表',
                    subtitle: '展示今日课程和下一节课',
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.course(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.course,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 16),
                  const _WidgetCatalogTile(
                    icon: Icons.edit_note_outlined,
                    title: '随手记',
                    subtitle: '展示最近更新的三条笔记，点击进入随手记',
                    color: Colors.purple,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.note(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.note,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 16),
                  const _WidgetCatalogTile(
                    icon: Icons.event_available_outlined,
                    title: '纪念日',
                    subtitle: '展示最近的纪念日，点击进入纪念日列表',
                    color: Colors.pink,
                  ),
                  const SizedBox(height: 10),
                  WidgetPreviewCard.anniversary(displayMode: _displayMode),
                  const SizedBox(height: 8),
                  _AddWidgetButton(
                    pinSupport: _pinSupport,
                    checkingPinSupport: _checkingPinSupport,
                    kind: DuoyiWidgetKind.anniversary,
                    displayMode: _displayMode,
                    canOpenWidgetSettings: _canOpenWidgetSettings,
                    onPinSupportChanged: _setPinSupport,
                  ),
                  const SizedBox(height: 12),
                  AppInfoBanner(
                    icon: Icons.touch_app_outlined,
                    color: Colors.teal,
                    title: '添加桌面无权限时的处理',
                    message:
                        '这里选择的是新添加小组件的默认样式/请求尺寸；已添加到桌面的实例不会被修改。系统小组件列表也提供紧凑 2×2、标准 3×2 和详细 4×3 入口。',
                  ),
                ],
              ),
      ),
    );
  }
}

class _DesktopWebWidgetFallback extends StatelessWidget {
  const _DesktopWebWidgetFallback();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('desktop_web_widget_fallback'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        AppInfoBanner(
          icon: Icons.desktop_windows_outlined,
          color: cs.primary,
          title: '电脑网页版显示日历',
          message: '桌面小组件依赖 Android 或 iOS 系统；电脑网页版默认隐藏小组件入口，保留月历预览和日历入口。',
        ),
        const SizedBox(height: 12),
        const _WidgetCatalogTile(
          icon: Icons.calendar_month_outlined,
          title: '月历',
          subtitle: '电脑网页版默认展示日历，不显示添加桌面小组件按钮',
          color: Colors.indigo,
        ),
        const SizedBox(height: 10),
        const WidgetPreviewCard.calendar(
          displayMode: WidgetDisplayMode.detailed,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CalendarScreen())),
            style: appSecondaryFilledButtonStyle(context),
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text('打开日历'),
          ),
        ),
      ],
    );
  }
}

class _WidgetPinSupportBanner extends StatelessWidget {
  final AndroidWidgetPinResult? result;
  final bool checking;
  final bool canOpenSettings;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  const _WidgetPinSupportBanner({
    required this.result,
    required this.checking,
    required this.canOpenSettings,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final support = result;
    final supported = support == AndroidWidgetPinResult.requested;
    final blocked =
        support == AndroidWidgetPinResult.unsupportedLauncher ||
        support == AndroidWidgetPinResult.unsupportedPlatform ||
        support == AndroidWidgetPinResult.unavailable;
    final color = checking
        ? Colors.blueGrey
        : supported
        ? Colors.teal
        : blocked
        ? Colors.orange
        : Colors.blueGrey;
    final title = checking
        ? '正在检查桌面小组件支持'
        : supported
        ? '当前桌面支持应用内添加'
        : switch (support) {
            AndroidWidgetPinResult.unsupportedPlatform => '当前平台不支持应用内添加',
            AndroidWidgetPinResult.unsupportedLauncher => '当前桌面不支持应用内添加',
            AndroidWidgetPinResult.permissionDenied => '桌面添加权限未通过',
            AndroidWidgetPinResult.confirmationBlocked => '桌面确认弹窗可能被拦截',
            AndroidWidgetPinResult.invalidKind => '当前小组件类型不可添加',
            _ => '当前桌面可能不支持应用内添加',
          };
    final message = checking
        ? '正在检测当前桌面是否支持直接固定小组件。'
        : supported
        ? '选择紧凑 2×2、标准 3×2 或详细 4×3 后再添加；这是新添加实例的请求尺寸，最终占位仍由桌面网格决定。'
        : switch (support) {
            AndroidWidgetPinResult.unsupportedPlatform =>
              '请在 Android 手机上使用系统小组件列表添加多仪，可选择紧凑 2×2、标准 3×2 或详细 4×3。',
            AndroidWidgetPinResult.unsupportedLauncher =>
              '当前桌面启动器未开放应用内添加；请从系统小组件列表选择紧凑 2×2、标准 3×2 或详细 4×3。',
            AndroidWidgetPinResult.permissionDenied =>
              '系统拒绝了添加请求，通常是桌面小组件权限未允许。请在系统设置里允许多仪添加桌面小组件后重试，或从系统小组件列表选择尺寸。',
            AndroidWidgetPinResult.confirmationBlocked =>
              '桌面没有展示或接受系统确认弹窗，常见于后台弹窗/悬浮窗限制。请允许多仪显示系统确认后重试，或从系统小组件列表选择尺寸。',
            AndroidWidgetPinResult.invalidKind => '请更新应用后重试。',
            _ => '如果点击添加后没有系统确认框，请打开系统设置检查桌面小组件权限、后台弹窗权限后重试，或从系统小组件列表选择尺寸。',
          };
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(8),
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              supported ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (canOpenSettings) ...[
                TextButton.icon(
                  onPressed: checking ? null : onOpenSettings,
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('打开应用设置'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: appSecondaryControlTextStyle(context),
                  ),
                ),
                const SizedBox(height: 2),
              ],
              TextButton.icon(
                onPressed: checking ? null : onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新检测'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: appSecondaryControlTextStyle(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum WidgetDisplayMode {
  compact('compact', '紧凑', '新添加时请求 2x2，只保留最关键的一行内容', '2x2', 1.0, 320),
  standard('standard', '标准', '新添加时请求 3x2，展示两行内容', '3x2', 1.5, 480),
  detailed('detailed', '详细', '新添加时请求 4x3，展示三行内容', '4x3', 4 / 3, 640);

  final String id;
  final String label;
  final String description;
  final String previewCellLabel;
  final double previewAspectRatio;
  final double previewMaxWidth;

  const WidgetDisplayMode(
    this.id,
    this.label,
    this.description,
    this.previewCellLabel,
    this.previewAspectRatio,
    this.previewMaxWidth,
  );

  static WidgetDisplayMode fromId(String? id) {
    return WidgetDisplayMode.values.firstWhere(
      (mode) => mode.id == id,
      orElse: () => WidgetDisplayMode.standard,
    );
  }

  AndroidWidgetStyle get androidStyle {
    return AndroidWidgetStyle.fromId(id);
  }

  String get launcherRequestLabel => previewCellLabel.replaceAll('x', '×');
}

class _WidgetDisplayModePanel extends StatelessWidget {
  final WidgetDisplayMode value;
  final ValueChanged<WidgetDisplayMode> onChanged;

  const _WidgetDisplayModePanel({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '新添加默认样式',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final segmented = SegmentedButton<WidgetDisplayMode>(
                segments: [
                  for (final mode in WidgetDisplayMode.values)
                    ButtonSegment(
                      value: mode,
                      label: Text(
                        '${mode.label} ${mode.launcherRequestLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                selected: {value},
                showSelectedIcon: false,
                onSelectionChanged: (next) => onChanged(next.single),
              );
              if (constraints.maxWidth >= 340) {
                return segmented;
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: segmented,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            value.description,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AddWidgetButton extends StatefulWidget {
  final DuoyiWidgetKind kind;
  final WidgetDisplayMode displayMode;
  final AndroidWidgetPinResult? pinSupport;
  final bool checkingPinSupport;
  final bool canOpenWidgetSettings;
  final ValueChanged<AndroidWidgetPinResult> onPinSupportChanged;

  const _AddWidgetButton({
    required this.kind,
    required this.displayMode,
    required this.pinSupport,
    required this.checkingPinSupport,
    required this.canOpenWidgetSettings,
    required this.onPinSupportChanged,
  });

  @override
  State<_AddWidgetButton> createState() => _AddWidgetButtonState();
}

class _AddWidgetButtonState extends State<_AddWidgetButton> {
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    final support = widget.pinSupport;
    final disabledByPlatform =
        !widget.checkingPinSupport &&
        support != null &&
        support != AndroidWidgetPinResult.requested;
    final label = widget.checkingPinSupport
        ? '正在检查桌面支持'
        : disabledByPlatform
        ? switch (support) {
            AndroidWidgetPinResult.unsupportedPlatform => '仅 Android 支持应用内添加',
            AndroidWidgetPinResult.unsupportedLauncher => '请从系统小组件列表添加',
            AndroidWidgetPinResult.unavailable => '查看添加帮助',
            _ => '查看添加帮助',
          }
        : _requesting
        ? '正在请求添加'
        : '添加${widget.displayMode.label} ${widget.displayMode.launcherRequestLabel}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 280.0;
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: FilledButton.icon(
              onPressed: _requesting || widget.checkingPinSupport
                  ? null
                  : disabledByPlatform
                  ? () => _showPinWidgetHelp(context, support)
                  : () => _request(context),
              style: appSecondaryFilledButtonStyle(context),
              icon: _requesting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      disabledByPlatform
                          ? Icons.help_outline
                          : Icons.add_to_home_screen_outlined,
                    ),
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _request(BuildContext context) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final support = await AndroidWidgetManager.checkPinSupport();
      if (!context.mounted) return;
      widget.onPinSupportChanged(support);
      if (support != AndroidWidgetPinResult.requested) {
        await AndroidWidgetManager.refreshAllWidgets();
        if (!context.mounted) return;
        await _showPinWidgetHelp(context, support);
        return;
      }
      final request = await AndroidWidgetManager.requestPinWidgetDetailed(
        widget.kind,
        style: widget.displayMode.androidStyle,
      );
      if (!context.mounted) return;
      if (request.result == AndroidWidgetPinResult.requested) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '等待桌面确认${widget.displayMode.label} ${widget.displayMode.launcherRequestLabel} 小组件；这是新添加实例的请求尺寸，不会修改已添加实例。',
            ),
          ),
        );
        final requestId = request.requestId;
        if (requestId == null || requestId.isEmpty) return;
        final confirmation = await AndroidWidgetManager.waitForPinResult(
          requestId,
        );
        if (!context.mounted) return;
        if (confirmation.isSuccess) {
          await AndroidWidgetManager.refreshAllWidgets();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已添加${widget.displayMode.label} ${widget.displayMode.launcherRequestLabel} 小组件到桌面。',
              ),
            ),
          );
          await AndroidWidgetManager.clearPinResult(requestId);
          return;
        }
        await AndroidWidgetManager.refreshAllWidgets();
        if (!context.mounted) return;
        await _showPinWidgetConfirmationFailureHelp(context, confirmation);
        return;
      }
      await AndroidWidgetManager.refreshAllWidgets();
      if (!context.mounted) return;
      await _showPinWidgetHelp(context, request.result);
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  Future<void> _showPinWidgetHelp(
    BuildContext context,
    AndroidWidgetPinResult result,
  ) async {
    final message = switch (result) {
      AndroidWidgetPinResult.unsupported =>
        '当前桌面不支持应用内直接添加小组件。请从系统小组件列表选择紧凑 2×2、标准 3×2 或详细 4×3。',
      AndroidWidgetPinResult.unsupportedPlatform =>
        '当前平台不支持直接添加 Android 桌面小组件。请在 Android 手机上使用系统小组件列表添加多仪，可选择紧凑 2×2、标准 3×2 或详细 4×3。',
      AndroidWidgetPinResult.unsupportedLauncher =>
        '当前桌面启动器不支持应用内直接添加小组件。请从系统小组件列表选择紧凑 2×2、标准 3×2 或详细 4×3。',
      AndroidWidgetPinResult.permissionDenied =>
        '系统拒绝了本次添加请求，通常是桌面小组件权限未允许；也可能没有桌面添加权限。请在系统设置里允许多仪添加桌面小组件后重试，或从系统小组件列表选择尺寸。',
      AndroidWidgetPinResult.confirmationBlocked =>
        '桌面没有展示或接受系统确认弹窗，常见于后台弹出确认、后台弹窗或悬浮窗限制，或桌面拦截了确认流程。请允许多仪显示系统确认后重试，或从系统小组件列表选择尺寸。',
      AndroidWidgetPinResult.invalidKind => '当前小组件类型暂不支持添加，请更新应用后重试。',
      AndroidWidgetPinResult.unavailable =>
        '无法发起添加到桌面。可打开系统设置检查桌面小组件权限、后台弹窗权限后重试，或从系统小组件列表选择尺寸。',
      AndroidWidgetPinResult.requested => '已发起添加请求，请在桌面确认小组件。',
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('添加到桌面'),
        content: Text(message),
        actions: [
          if (widget.canOpenWidgetSettings)
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _openWidgetSettings(context);
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('打开权限设置'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: appSecondaryFilledButtonStyle(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPinWidgetConfirmationFailureHelp(
    BuildContext context,
    AndroidWidgetPinConfirmation confirmation,
  ) async {
    final (title, message) = switch (confirmation.status) {
      AndroidWidgetPinFinalStatus.invalidWidgetId => (
        '添加未完成',
        '桌面返回了无效的小组件实例，系统没有真正创建桌面小组件。请重新点击添加；如果反复出现，请切换标准尺寸或在系统小组件列表中添加。',
      ),
      AndroidWidgetPinFinalStatus.timeout => (
        '等待桌面确认',
        '已发起添加请求，但桌面暂未返回确认结果。部分桌面会延迟回调，可先回到桌面查看；如果一直没有确认弹窗，请检查桌面小组件权限和后台弹窗权限，或从系统小组件列表选择尺寸。',
      ),
      AndroidWidgetPinFinalStatus.unavailable => (
        '添加状态异常',
        '桌面没有返回有效的添加结果。请重新点击添加；如果反复失败，请检查桌面小组件权限、后台弹窗权限，或从系统小组件列表添加标准尺寸。',
      ),
      AndroidWidgetPinFinalStatus.success => ('已添加', '桌面小组件已添加。'),
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (widget.canOpenWidgetSettings)
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _openWidgetSettings(context);
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('打开权限设置'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: appSecondaryFilledButtonStyle(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _openWidgetSettings(BuildContext context) async {
    final opened = await AndroidWidgetManager.openWidgetSettings();
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开应用设置，请手动进入系统设置检查多仪权限')));
    }
  }
}

class WidgetPreviewCard extends StatelessWidget {
  final WidgetPreviewKind kind;
  final WidgetDisplayMode displayMode;

  const WidgetPreviewCard.todo({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.todo;
  const WidgetPreviewCard.focus({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.focus;
  const WidgetPreviewCard.habit({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.habit;
  const WidgetPreviewCard.calendar({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.calendar;
  const WidgetPreviewCard.schedule({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.schedule;
  const WidgetPreviewCard.goal({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.goal;
  const WidgetPreviewCard.course({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.course;
  const WidgetPreviewCard.note({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.note;
  const WidgetPreviewCard.anniversary({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.anniversary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    ThemeProvider? themeProvider;
    try {
      themeProvider = context.watch<ThemeProvider>();
    } catch (_) {
      themeProvider = null;
    }
    final cardSkin = themeProvider?.activeCardSkin;
    final usesCardSkin =
        cardSkin != null && cardSkin.id != ThemeProvider.defaultCardSkinId;
    final accent = switch (kind) {
      WidgetPreviewKind.todo => Colors.blue,
      WidgetPreviewKind.focus => Colors.redAccent,
      WidgetPreviewKind.habit => Colors.green,
      WidgetPreviewKind.calendar => Colors.indigo,
      WidgetPreviewKind.schedule => Colors.cyan,
      WidgetPreviewKind.goal => Colors.orange,
      WidgetPreviewKind.course => Colors.orange,
      WidgetPreviewKind.note => Colors.purple,
      WidgetPreviewKind.anniversary => Colors.pink,
    };
    final title = switch (kind) {
      WidgetPreviewKind.todo => '今日待办预览',
      WidgetPreviewKind.focus => '专注预览',
      WidgetPreviewKind.habit => '习惯预览',
      WidgetPreviewKind.calendar => '月历预览',
      WidgetPreviewKind.schedule => '今日日程预览',
      WidgetPreviewKind.goal => '目标预览',
      WidgetPreviewKind.course => '课程表预览',
      WidgetPreviewKind.note => '随手记预览',
      WidgetPreviewKind.anniversary => '纪念日预览',
    };
    final skin = cardSkin;
    final widgetBrand = themeProvider?.activeWidgetBackgroundBrand;
    final previewBackgroundAsset = widgetBrand?.backgroundAsset;
    final imageBacked = previewBackgroundAsset != null;
    final brightness = Theme.of(context).brightness;
    final backgroundStart = usesCardSkin && skin != null
        ? skin.colors.first
        : cs.primary;
    final backgroundEnd = usesCardSkin && skin != null
        ? skin.colors.last
        : cs.surface;
    final previewBackground = Color.alphaBlend(
      backgroundStart.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12,
      ),
      cs.surface,
    );
    final previewGradient = LinearGradient(
      colors: [
        previewBackground,
        Color.alphaBlend(
          backgroundEnd.withValues(
            alpha: usesCardSkin
                ? (Theme.of(context).brightness == Brightness.dark
                      ? 0.20
                      : 0.14)
                : 0.05,
          ),
          cs.surface,
        ),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final imageOverlay = LinearGradient(
      colors: brightness == Brightness.dark
          ? [
              Colors.black.withValues(alpha: 0.34),
              cs.surface.withValues(alpha: 0.46),
            ]
          : [
              (widgetBrand?.backgroundOverlay ?? cs.surface).withValues(
                alpha: 0.42,
              ),
              cs.surface.withValues(alpha: 0.58),
            ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return Semantics(
      label: '$title ${displayMode.previewCellLabel}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : displayMode.previewMaxWidth;
          final width = available < displayMode.previewMaxWidth
              ? available
              : displayMode.previewMaxWidth;
          return Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: width,
              child: AspectRatio(
                aspectRatio: displayMode.previewAspectRatio,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: imageBacked ? cs.surface : previewBackground,
                    gradient: imageBacked ? null : previewGradient,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.16),
                      width: 0.45,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (imageBacked)
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final dpr = MediaQuery.devicePixelRatioOf(
                                context,
                              ).clamp(1.0, 3.0);
                              final cacheWidth = (constraints.maxWidth * dpr)
                                  .ceil()
                                  .clamp(1, 1600);
                              final cacheHeight = (constraints.maxHeight * dpr)
                                  .ceil()
                                  .clamp(1, 1600);
                              return Image.asset(
                                previewBackgroundAsset,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                cacheWidth: cacheWidth,
                                cacheHeight: cacheHeight,
                                filterQuality: FilterQuality.low,
                                gaplessPlayback: true,
                                errorBuilder: (context, error, stack) =>
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: previewGradient,
                                      ),
                                    ),
                              );
                            },
                          ),
                        ),
                      if (imageBacked)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: imageOverlay),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Image.asset(
                                  'assets/logo/duoyi_web_logo_512.png',
                                  width: 24,
                                  height: 24,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: DesignTokens.fontWeightStrong,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${displayMode.previewCellLabel} · 05/17',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _WidgetPreviewContentFrame(
                                mode: displayMode,
                                child: switch (kind) {
                                  WidgetPreviewKind.todo =>
                                    const _WidgetPreviewTodoBody(),
                                  WidgetPreviewKind.focus =>
                                    const _WidgetPreviewFocusBody(),
                                  WidgetPreviewKind.habit =>
                                    const _WidgetPreviewHabitBody(),
                                  WidgetPreviewKind.calendar =>
                                    const _WidgetPreviewCalendarBody(),
                                  WidgetPreviewKind.schedule =>
                                    const _WidgetPreviewScheduleBody(),
                                  WidgetPreviewKind.goal =>
                                    const _WidgetPreviewGoalBody(),
                                  WidgetPreviewKind.course =>
                                    const _WidgetPreviewCourseBody(),
                                  WidgetPreviewKind.note =>
                                    const _WidgetPreviewNoteBody(),
                                  WidgetPreviewKind.anniversary =>
                                    const _WidgetPreviewAnniversaryBody(),
                                },
                              ),
                            ),
                            if (displayMode != WidgetDisplayMode.compact) ...[
                              const SizedBox(height: 10),
                              _WidgetPreviewNav(
                                selectedIndex: switch (kind) {
                                  WidgetPreviewKind.todo => 0,
                                  WidgetPreviewKind.focus => 3,
                                  WidgetPreviewKind.habit => 1,
                                  WidgetPreviewKind.calendar => 2,
                                  WidgetPreviewKind.schedule => 2,
                                  WidgetPreviewKind.goal => 2,
                                  WidgetPreviewKind.course => 2,
                                  WidgetPreviewKind.note => 2,
                                  WidgetPreviewKind.anniversary => 2,
                                },
                                accent: accent,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum WidgetPreviewKind {
  todo,
  focus,
  habit,
  calendar,
  schedule,
  goal,
  course,
  note,
  anniversary,
}

class _WidgetPreviewDensity extends StatelessWidget {
  final WidgetDisplayMode mode;
  final Widget child;

  const _WidgetPreviewDensity({required this.mode, required this.child});

  @override
  Widget build(BuildContext context) {
    final maxLines = switch (mode) {
      WidgetDisplayMode.compact => 1,
      WidgetDisplayMode.standard => 2,
      WidgetDisplayMode.detailed => 3,
    };
    return _WidgetPreviewDensityScope(maxLines: maxLines, child: child);
  }
}

class _WidgetPreviewContentFrame extends StatelessWidget {
  final WidgetDisplayMode mode;
  final Widget child;

  const _WidgetPreviewContentFrame({required this.mode, required this.child});

  @override
  Widget build(BuildContext context) {
    final designHeight = switch (mode) {
      WidgetDisplayMode.compact => 92.0,
      WidgetDisplayMode.standard => 150.0,
      WidgetDisplayMode.detailed => 200.0,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mode.previewMaxWidth;
        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: designHeight,
                child: _WidgetPreviewDensity(mode: mode, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WidgetPreviewDensityScope extends InheritedWidget {
  final int maxLines;

  const _WidgetPreviewDensityScope({
    required this.maxLines,
    required super.child,
  });

  static int maxLinesOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_WidgetPreviewDensityScope>()
            ?.maxLines ??
        2;
  }

  @override
  bool updateShouldNotify(_WidgetPreviewDensityScope oldWidget) {
    return maxLines != oldWidget.maxLines;
  }
}

class _WidgetPreviewTodoBody extends StatelessWidget {
  const _WidgetPreviewTodoBody();

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    return Column(
      children: [
        const _WidgetPreviewLine(
          icon: Icons.warning_amber_outlined,
          text: '逾期 1 项 · 20:25 有提醒 · 今日优先处理',
        ),
        const SizedBox(height: 5),
        const _WidgetPreviewTodoRow(text: '整理今日计划'),
        if (maxLines >= 2) ...[
          const SizedBox(height: 7),
          const _WidgetPreviewTodoRow(text: '项目复盘 · 3 个子任务'),
        ],
        if (maxLines >= 3) ...[
          const SizedBox(height: 7),
          const _WidgetPreviewTodoRow(text: '晚间运动 30 分钟'),
          const SizedBox(height: 5),
          const _WidgetPreviewLine(
            icon: Icons.subdirectory_arrow_right,
            text: 'AI 子任务：列清单 / 订闹钟 / 完成确认 / 今日可见',
          ),
        ],
      ],
    );
  }
}

class _WidgetPreviewFocusBody extends StatelessWidget {
  const _WidgetPreviewFocusBody();

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: _WidgetPreviewMetric(
                value: '2',
                label: '专注',
                color: Colors.redAccent,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '50',
                label: '分钟',
                color: Colors.redAccent,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '25',
                label: '下一轮',
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '开始 25 分钟专注',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        if (maxLines >= 2) ...[
          const SizedBox(height: 8),
          const _WidgetPreviewLine(
            icon: Icons.timer_outlined,
            text: '今日专注 2 次 · 深度工作 50 分钟',
          ),
        ],
        if (maxLines >= 3) ...[
          const _WidgetPreviewLine(
            icon: Icons.play_circle_outline,
            text: '下一轮 25 分钟 · 点击立即开始',
          ),
          const _WidgetPreviewLine(
            icon: Icons.notifications_active_outlined,
            text: '结束后提醒休息 5 分钟',
          ),
        ],
      ],
    );
  }
}

class _WidgetPreviewHabitBody extends StatelessWidget {
  const _WidgetPreviewHabitBody();

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: _WidgetPreviewMetric(
                value: '4/5',
                label: '完成',
                color: Colors.green,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '80%',
                label: '进度',
                color: Colors.green,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '12',
                label: '连续',
                color: Colors.green,
              ),
            ),
          ],
        ),
        if (maxLines >= 2) ...[
          const SizedBox(height: 8),
          const _WidgetPreviewLine(
            icon: Icons.self_improvement_outlined,
            text: '晚间拉伸 · 今天待打卡',
          ),
        ],
        if (maxLines >= 3) ...[
          const _WidgetPreviewLine(
            icon: Icons.water_drop_outlined,
            text: '喝水 · 已记录 7 杯',
          ),
          const _WidgetPreviewLine(
            icon: Icons.local_fire_department_outlined,
            text: '连续记录 12 天',
          ),
        ],
      ],
    );
  }
}

class _WidgetPreviewCalendarBody extends StatelessWidget {
  const _WidgetPreviewCalendarBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    const currentWeekIndex = 2;
    final visibleWeeks = switch (maxLines) {
      1 => [currentWeekIndex],
      2 => [
        currentWeekIndex - 1,
        currentWeekIndex,
        currentWeekIndex + 1,
        currentWeekIndex + 2,
      ],
      _ => [0, 1, 2, 3, 4, 5],
    };
    const weekLabels = ['一', '二', '三', '四', '五', '六', '日'];
    const monthWeeks = <List<int?>>[
      [null, null, null, null, 1, 2, 3],
      [4, 5, 6, 7, 8, 9, 10],
      [11, 12, 13, 14, 15, 16, 17],
      [18, 19, 20, 21, 22, 23, 24],
      [25, 26, 27, 28, 29, 30, 31],
      [null, null, null, null, null, null, null],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '2026年5月',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.28),
                  width: 0.45,
                ),
              ),
              child: const Text(
                '今天',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 11,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        _WidgetPreviewCalendarGrid(
          weekLabels: weekLabels,
          weeks: [for (final index in visibleWeeks) monthWeeks[index]],
        ),
      ],
    );
  }
}

class _WidgetPreviewCalendarGrid extends StatelessWidget {
  final List<String> weekLabels;
  final List<List<int?>> weeks;

  const _WidgetPreviewCalendarGrid({
    required this.weekLabels,
    required this.weeks,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            for (final label in weekLabels)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final week in weeks) ...[
          Row(
            children: [
              for (final day in week)
                Expanded(child: _WidgetPreviewCalendarCell(day: day)),
            ],
          ),
          const SizedBox(height: 3),
        ],
      ],
    );
  }
}

class _WidgetPreviewCalendarCell extends StatelessWidget {
  final int? day;

  const _WidgetPreviewCalendarCell({required this.day});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isToday = day == 17;
    return Center(
      child: Container(
        width: 22,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isToday ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          day == null ? '' : '$day',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 10,
            color: isToday ? Colors.white : cs.onSurface,
            fontWeight: DesignTokens.fontWeightStrong,
          ),
        ),
      ),
    );
  }
}

class _WidgetPreviewScheduleBody extends StatelessWidget {
  const _WidgetPreviewScheduleBody();

  @override
  Widget build(BuildContext context) {
    return const _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.notifications_active_outlined,
          text: '20:25 厕所 · 到点提醒',
        ),
        _WidgetPreviewLine(icon: Icons.event_note_outlined, text: '14:30 团队例会'),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: '19:00 晚间复盘',
        ),
      ],
    );
  }
}

class _WidgetPreviewGoalBody extends StatelessWidget {
  const _WidgetPreviewGoalBody();

  @override
  Widget build(BuildContext context) {
    return const _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(icon: Icons.flag_outlined, text: '发版准备 · 68%'),
        _WidgetPreviewLine(
          icon: Icons.trending_up_outlined,
          text: '本周运动 3/5 次',
        ),
        _WidgetPreviewLine(
          icon: Icons.check_circle_outline,
          text: '晚间复盘 · 今日待推进',
        ),
      ],
    );
  }
}

class _WidgetPreviewCourseBody extends StatelessWidget {
  const _WidgetPreviewCourseBody();

  @override
  Widget build(BuildContext context) {
    return const _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.school_outlined,
          text: '第 1-2 节 高等数学 · 教 203',
        ),
        _WidgetPreviewLine(
          icon: Icons.school_outlined,
          text: '第 3-4 节 产品设计 · 线上',
        ),
        _WidgetPreviewLine(
          icon: Icons.event_note_outlined,
          text: '14:30 团队例会 · 打开日历查看',
        ),
      ],
    );
  }
}

class _WidgetPreviewNoteBody extends StatelessWidget {
  const _WidgetPreviewNoteBody();

  @override
  Widget build(BuildContext context) {
    return const _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(icon: Icons.edit_note_outlined, text: '会议纪要'),
        _WidgetPreviewLine(icon: Icons.lightbulb_outline, text: '灵感清单'),
        _WidgetPreviewLine(icon: Icons.menu_book_outlined, text: '读书摘录'),
      ],
    );
  }
}

class _WidgetPreviewAnniversaryBody extends StatelessWidget {
  const _WidgetPreviewAnniversaryBody();

  @override
  Widget build(BuildContext context) {
    return const _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: '相识纪念日 · 还有 6 天',
        ),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: '入职周年 · 还有 18 天',
        ),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: '旅行纪念 · 还有 32 天',
        ),
      ],
    );
  }
}

class _WidgetPreviewLineList extends StatelessWidget {
  final List<Widget> lines;

  const _WidgetPreviewLineList({required this.lines});

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in lines.take(maxLines)) line],
    );
  }
}

class _WidgetPreviewLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WidgetPreviewLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetPreviewTodoRow extends StatelessWidget {
  final String text;

  const _WidgetPreviewTodoRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.28),
              width: 0.45,
            ),
          ),
          child: const Text(
            'o',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: Colors.blue,
              fontSize: 13,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}

class _WidgetPreviewMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _WidgetPreviewMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: DesignTokens.fontWeightStrong,
            color: color,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _WidgetPreviewNav extends StatelessWidget {
  final int selectedIndex;
  final Color accent;

  const _WidgetPreviewNav({required this.selectedIndex, required this.accent});

  @override
  Widget build(BuildContext context) {
    const labels = ['待办', '习惯', '日历', '专注'];
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.18),
          width: 0.45,
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Center(
                child: Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: DesignTokens.fontWeightStrong,
                    color: i == selectedIndex ? accent : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WidgetCatalogTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _WidgetCatalogTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
