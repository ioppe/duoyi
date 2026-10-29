import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/home_widget_calendar.dart';
import '../core/home_widget_todos.dart';
import '../core/web_target.dart';
import '../core/i18n.dart';
import '../models/todo.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../services/android_widget_manager.dart';
import '../services/home_widget_service.dart';
import '../widgets/surface_components.dart';
import '../widgets/widget_brand_logo.dart';
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
    // Android 系统小组件列表只暴露核心 4 类（AndroidWidgetManager.catalogKinds）：
    // 5 个次级品类仍保留给已添加的旧实例刷新，但不再出现在应用内目录。
    final showSecondaryWidgetCatalog = !AndroidWidgetManager.isNativeAndroid;
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
                  _WidgetCatalogTile(
                    icon: Icons.calendar_month_outlined,
                    title: '月历',
                    subtitle: I18n.tr('widget.calendar_month_summary'),
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
                  if (showSecondaryWidgetCatalog) ...[
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
                  ],
                  const SizedBox(height: 12),
                  AppInfoBanner(
                    icon: Icons.touch_app_outlined,
                    color: Colors.teal,
                    title: '添加桌面无权限时的处理',
                    message: AndroidWidgetManager.isNativeAndroid
                        ? I18n.tr('widget.android_catalog_density_hint')
                        : '这里选择的是新添加小组件的默认样式/请求尺寸；已添加到桌面的实例不会被修改。系统小组件列表也提供紧凑 2×2、标准 3×2 和详细 4×3 入口。',
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
        ? I18n.tr('widget.android_picker_hint')
        : switch (support) {
            AndroidWidgetPinResult.unsupportedPlatform => I18n.tr(
              'widget.mobile_picker_hint',
            ),
            AndroidWidgetPinResult.unsupportedLauncher =>
              '当前桌面启动器未开放应用内添加。${I18n.tr('widget.android_picker_hint')}',
            AndroidWidgetPinResult.permissionDenied =>
              '系统拒绝了添加请求，通常是桌面小组件权限未允许。请在系统设置里允许多仪添加桌面小组件后重试。${I18n.tr('widget.android_picker_hint')}',
            AndroidWidgetPinResult.confirmationBlocked =>
              '桌面没有展示或接受系统确认弹窗，常见于后台弹窗/悬浮窗限制。请允许多仪显示系统确认后重试。${I18n.tr('widget.android_picker_hint')}',
            AndroidWidgetPinResult.invalidKind => '请更新应用后重试。',
            _ =>
              '如果点击添加后没有系统确认框，请打开系统设置检查桌面小组件权限、后台弹窗权限后重试。${I18n.tr('widget.android_picker_hint')}',
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
        '当前桌面不支持应用内直接添加小组件。${I18n.tr('widget.android_picker_hint')}',
      AndroidWidgetPinResult.unsupportedPlatform => I18n.tr(
        'widget.mobile_picker_hint',
      ),
      AndroidWidgetPinResult.unsupportedLauncher =>
        '当前桌面启动器不支持应用内直接添加小组件。${I18n.tr('widget.android_picker_hint')}',
      AndroidWidgetPinResult.permissionDenied =>
        '系统拒绝了本次添加请求，通常是桌面小组件权限未允许；也可能没有桌面添加权限。请在系统设置里允许多仪添加桌面小组件后重试。${I18n.tr('widget.android_picker_hint')}',
      AndroidWidgetPinResult.confirmationBlocked =>
        '桌面没有展示或接受系统确认弹窗，常见于后台弹出确认、后台弹窗或悬浮窗限制，或桌面拦截了确认流程。请允许多仪显示系统确认后重试。${I18n.tr('widget.android_picker_hint')}',
      AndroidWidgetPinResult.invalidKind => '当前小组件类型暂不支持添加，请更新应用后重试。',
      AndroidWidgetPinResult.unavailable =>
        '无法发起添加到桌面。可打开系统设置检查桌面小组件权限、后台弹窗权限后重试。${I18n.tr('widget.android_picker_hint')}',
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
        '桌面返回了无效的小组件实例，系统没有真正创建桌面小组件。请重新点击添加；如果反复出现，请从系统小组件列表重新添加。${I18n.tr('widget.android_picker_hint')}',
      ),
      AndroidWidgetPinFinalStatus.timeout => (
        '等待桌面确认',
        '已发起添加请求，但桌面暂未返回确认结果。部分桌面会延迟回调，可先回到桌面查看；如果一直没有确认弹窗，请检查桌面小组件权限和后台弹窗权限。${I18n.tr('widget.android_picker_hint')}',
      ),
      AndroidWidgetPinFinalStatus.unavailable => (
        '添加状态异常',
        '桌面没有返回有效的添加结果。请重新点击添加；如果反复失败，请检查桌面小组件权限、后台弹窗权限。${I18n.tr('widget.android_picker_hint')}',
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
    AppClock.watch(context);
    final previewToday = AppClock.today();
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
    // core 4 模块用苹果风样卡；secondary 5 模块保持原样。
    final apple = _usesApplePreview(kind);
    final palette = _ApplePreviewPalette.of(context, cs);
    final navLabels = _appleNavLabels(themeProvider);
    final todayTodos = kind == WidgetPreviewKind.todo
        ? _watchTodayTodos(context, previewToday)
        : null;
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
                    color: apple
                        ? palette.surface
                        : (imageBacked ? cs.surface : previewBackground),
                    gradient: (apple || imageBacked) ? null : previewGradient,
                    borderRadius: BorderRadius.circular(apple ? 24 : 12),
                    border: apple
                        ? null
                        : Border.all(
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
                            decoration: BoxDecoration(
                              gradient: apple
                                  ? palette.imageOverlay
                                  : imageOverlay,
                            ),
                          ),
                        ),
                      if (apple)
                        _WidgetApplePreview(
                          kind: kind,
                          displayMode: displayMode,
                          palette: palette,
                          navLabels: navLabels,
                          today: previewToday,
                          todos: todayTodos,
                        ),
                      if (!apple)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const WidgetBrandLogo(size: 24),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight:
                                            DesignTokens.fontWeightStrong,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${displayMode.previewCellLabel} · '
                                    '${previewToday.month.toString().padLeft(2, '0')}/'
                                    '${previewToday.day.toString().padLeft(2, '0')}',
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
                                  designHeightOverride:
                                      kind == WidgetPreviewKind.calendar
                                      ? _WidgetPreviewCalendarBody.designHeightFor(
                                          displayMode,
                                        )
                                      : null,
                                  child: switch (kind) {
                                    WidgetPreviewKind.todo =>
                                      const _WidgetPreviewTodoBody(),
                                    WidgetPreviewKind.focus =>
                                      const _WidgetPreviewFocusBody(),
                                    WidgetPreviewKind.habit =>
                                      const _WidgetPreviewHabitBody(),
                                    WidgetPreviewKind.calendar =>
                                      _WidgetPreviewCalendarBody(
                                        displayMode: displayMode,
                                      ),
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

  /// 完整月历等内容较多的预览可抬高设计高度；默认仍按密度取值。
  final double? designHeightOverride;

  /// 内容比可用空间大时按比例缩小；苹果风样卡水平居中，其它预览保持左上。
  final Alignment alignment;

  const _WidgetPreviewContentFrame({
    required this.mode,
    required this.child,
    this.designHeightOverride,
    this.alignment = Alignment.topLeft,
  });

  @override
  Widget build(BuildContext context) {
    final designHeight =
        designHeightOverride ??
        switch (mode) {
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
            alignment: alignment,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: alignment,
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
  /// null = 独立预览（无 TodoProvider）时用示例列表；空列表 = 真实今日无待办。
  final List<TodoItem>? todos;
  final String navTodoLabel;

  const _WidgetPreviewTodoBody({this.todos, this.navTodoLabel = ''});

  @override
  Widget build(BuildContext context) {
    final palette = _ApplePreviewPalette.of(
      context,
      Theme.of(context).colorScheme,
    );
    final visible = todos;
    if (visible != null && visible.isEmpty) {
      return _WidgetTodoAppleEmptyNotice(
        palette: palette,
        navTodoLabel: navTodoLabel,
      );
    }
    // 有 Provider 时渲染完整列表（不在数据层截断），由有界 ListView 滚动浏览；
    // 无 Provider（独立预览/组件测试）才退回到三条示例。
    final rows = visible == null
        ? const <Widget>[
            _WidgetPreviewTodoRow(text: '整理今日计划'),
            _WidgetPreviewTodoRow(text: '项目复盘 · 3 个子任务'),
            _WidgetPreviewTodoRow(text: '晚间运动 30 分钟'),
          ]
        : <Widget>[
            for (final todo in visible) _WidgetPreviewTodoRow(text: todo.title),
          ];
    return ListView.separated(
      key: const ValueKey('widget-preview-todo-list'),
      padding: EdgeInsets.zero,
      // 固定 key + 外部固定高度：数据刷新不重置滚动位置。
      physics: const ClampingScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: palette.ink.withValues(alpha: 0.06),
      ),
      itemBuilder: (context, index) => rows[index],
    );
  }
}

/// 待办空态：居中灰勾圆 + 既有文案 + 新提示，不再堆告警和 AI 说明。
class _WidgetTodoAppleEmptyNotice extends StatelessWidget {
  final _ApplePreviewPalette palette;
  final String navTodoLabel;

  const _WidgetTodoAppleEmptyNotice({
    required this.palette,
    required this.navTodoLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tabLabel = navTodoLabel.isEmpty ? I18n.tr('nav.todo') : navTodoLabel;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 26,
          color: palette.secondary.withValues(alpha: 0.72),
        ),
        const SizedBox(height: 8),
        Text(
          I18n.tr('widget.todo_top3_empty'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: DesignTokens.fontWeightMedium,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          I18n.tr('widget.todo_empty_hint').replaceAll('{tab}', tabLabel),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.4, color: palette.secondary),
        ),
      ],
    );
  }
}

/// 专注预览：三个控制按钮（开始/继续、暂停、停止）替换原“前往专注”入口。
///
/// 纯预览演示：状态与倒计时只在本组件内 tick，**不触碰真实 `PomodoroProvider`**；
/// 原生真实控制由桌面小组件后台动作完成。首按钮在暂停后显示“继续”。
class _WidgetPreviewFocusBody extends StatefulWidget {
  const _WidgetPreviewFocusBody();

  @override
  State<_WidgetPreviewFocusBody> createState() =>
      _WidgetPreviewFocusBodyState();
}

enum _FocusPreviewPhase { idle, running, paused }

class _WidgetPreviewFocusBodyState extends State<_WidgetPreviewFocusBody> {
  static const int _totalSeconds = 25 * 60;

  _FocusPreviewPhase _phase = _FocusPreviewPhase.idle;
  int _remainingSeconds = _totalSeconds;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startOrResume() {
    if (_phase == _FocusPreviewPhase.running) return;
    setState(() => _phase = _FocusPreviewPhase.running);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        _stop();
        return;
      }
      setState(() => _remainingSeconds--);
    });
  }

  void _pause() {
    if (_phase != _FocusPreviewPhase.running) return;
    _ticker?.cancel();
    _ticker = null;
    setState(() => _phase = _FocusPreviewPhase.paused);
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _phase = _FocusPreviewPhase.idle;
      _remainingSeconds = _totalSeconds;
    });
  }

  String get _timeLabel {
    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final palette = _ApplePreviewPalette.of(
      context,
      Theme.of(context).colorScheme,
    );
    final startLabel = _phase == _FocusPreviewPhase.paused
        ? I18n.tr('widget.focus_resume_label')
        : I18n.tr('widget.focus_start_label');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _timeLabel,
                  key: const ValueKey('widget-preview-focus-time'),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeWidgetPrimaryMetric,
                    height: 1.05,
                    letterSpacing: -0.8,
                    fontWeight: DesignTokens.fontWeightStrong,
                    color: palette.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _phase == _FocusPreviewPhase.paused
                  ? I18n.tr('widget.focus_paused_label')
                  : _phase == _FocusPreviewPhase.running
                  ? I18n.tr('widget.focus_running_label')
                  : I18n.tr('widget.focus_next_label'),
              key: const ValueKey('widget-preview-focus-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.secondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _WidgetPreviewFocusButton(
                buttonKey: const ValueKey('widget-preview-focus-start'),
                label: startLabel,
                palette: palette,
                emphasized: true,
                onTap: _startOrResume,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _WidgetPreviewFocusButton(
                buttonKey: const ValueKey('widget-preview-focus-pause'),
                label: I18n.tr('widget.focus_pause_label'),
                palette: palette,
                onTap: _pause,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _WidgetPreviewFocusButton(
                buttonKey: const ValueKey('widget-preview-focus-stop'),
                label: I18n.tr('widget.focus_stop_label'),
                palette: palette,
                onTap: _stop,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WidgetPreviewFocusButton extends StatelessWidget {
  final Key buttonKey;
  final String label;
  final _ApplePreviewPalette palette;
  final bool emphasized;
  final VoidCallback onTap;

  const _WidgetPreviewFocusButton({
    required this.buttonKey,
    required this.label,
    required this.palette,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 26,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: emphasized
              ? palette.accent.withValues(alpha: 0.12)
              : palette.track,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: DesignTokens.fontWeightMedium,
            color: emphasized ? palette.accent : palette.ink,
          ),
        ),
      ),
    );
  }
}

class _WidgetPreviewHabitBody extends StatelessWidget {
  const _WidgetPreviewHabitBody();

  @override
  Widget build(BuildContext context) {
    final palette = _ApplePreviewPalette.of(
      context,
      Theme.of(context).colorScheme,
    );
    // 示例数据与原 demo 一致（4/5 完成、80%、连续 12 天），不改 HabitProvider。
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '80%',
          maxLines: 1,
          style: TextStyle(
            fontSize: DesignTokens.fontSizeWidgetPrimaryMetric,
            height: 1.1,
            letterSpacing: -1,
            fontWeight: DesignTokens.fontWeightStrong,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          I18n.tr('widget.habit_today_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: palette.secondary),
        ),
        const SizedBox(height: 8),
        Text(
          '${I18n.tr('widget.streak_record_prefix')}12'
          '${I18n.tr('widget.streak_suffix')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: palette.ink),
        ),
      ],
    );
  }
}

/// 固定单月预览：沿用原来的正文设计高度、星期表头和完整 4-6 周网格。
/// 月份标题放回外层头栏，正文不再插入标题或纵向月份列表。
class _WidgetPreviewCalendarBody extends StatefulWidget {
  final WidgetDisplayMode displayMode;

  const _WidgetPreviewCalendarBody({super.key, required this.displayMode});

  static double designHeightFor(WidgetDisplayMode mode) => switch (mode) {
    WidgetDisplayMode.compact => 132.0,
    WidgetDisplayMode.standard => 150.0,
    WidgetDisplayMode.detailed => 200.0,
  };

  @override
  State<_WidgetPreviewCalendarBody> createState() =>
      _WidgetPreviewCalendarBodyState();
}

class _WidgetPreviewCalendarBodyState
    extends State<_WidgetPreviewCalendarBody> {
  void refreshCurrentMonth() => setState(() {});

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final today = AppClock.today();
    final month = DateTime(today.year, today.month);
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    TodoProvider? todoProvider;
    try {
      todoProvider = context.watch<TodoProvider>();
    } catch (_) {
      // 组件测试和独立预览允许不注入业务 Provider。
      todoProvider = null;
    }
    final dayCounts = buildHomeWidgetCalendarDayCounts(
      todoProvider?.todos ?? const <TodoItem>[],
    );
    final dateFontSize = switch (widget.displayMode) {
      WidgetDisplayMode.compact => 10.0,
      WidgetDisplayMode.standard => 11.0,
      WidgetDisplayMode.detailed => 12.0,
    };
    return SizedBox.expand(
      key: ValueKey('widget-calendar-month-$monthKey'),
      child: _WidgetPreviewCalendarGrid(
        key: const ValueKey('widget-preview-calendar-month-grid'),
        weekdayLabels: homeWidgetCalendarWeekdayLabels(),
        weeks: buildHomeWidgetCalendarWeeks(month),
        dayCounts: dayCounts,
        today: today,
        dateFontSize: dateFontSize,
      ),
    );
  }
}

class _WidgetPreviewCalendarGrid extends StatelessWidget {
  final List<String> weekdayLabels;
  final List<List<DateTime?>> weeks;
  final Map<String, int> dayCounts;
  final DateTime today;
  final double dateFontSize;

  const _WidgetPreviewCalendarGrid({
    super.key,
    required this.weekdayLabels,
    required this.weeks,
    required this.dayCounts,
    required this.today,
    required this.dateFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _ApplePreviewPalette.of(
      context,
      Theme.of(context).colorScheme,
    );
    return Column(
      children: [
        Row(
          children: [
            for (final label in weekdayLabels)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 9, color: palette.secondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Column(
            children: [
              for (var index = 0; index < weeks.length; index++)
                Expanded(
                  child: Row(
                    key: ValueKey('widget-calendar-week-$index'),
                    children: [
                      for (final date in weeks[index])
                        Expanded(
                          child: _WidgetPreviewCalendarCell(
                            date: date,
                            count: date == null
                                ? 0
                                : dayCounts[homeWidgetCalendarDayKey(date)] ??
                                      0,
                            isToday:
                                date != null &&
                                date.year == today.year &&
                                date.month == today.month &&
                                date.day == today.day,
                            dateFontSize: dateFontSize,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WidgetPreviewCalendarCell extends StatelessWidget {
  final DateTime? date;
  final int count;
  final bool isToday;
  final double dateFontSize;

  const _WidgetPreviewCalendarCell({
    required this.date,
    required this.count,
    required this.isToday,
    required this.dateFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final value = date;
    if (value == null) return const SizedBox.shrink();
    final palette = _ApplePreviewPalette.of(
      context,
      Theme.of(context).colorScheme,
    );
    final dayKey = homeWidgetCalendarDayKey(value);
    final countLabel = count > 0
        ? I18n.tr(
            'widget.calendar_day_count_label',
          ).replaceAll('{date}', dayKey).replaceAll('{count}', '$count')
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 32.0;
        final badgeHeight = (height * 0.32).clamp(0.0, 12.0).toDouble();
        final gap = (height * 0.04).clamp(0.0, 1.0).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: badgeHeight,
              child: Align(
                alignment: Alignment.topRight,
                child: countLabel == null
                    ? null
                    : Semantics(
                        label: countLabel,
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 1),
                            child: Container(
                              key: ValueKey('widget-calendar-badge-$dayKey'),
                              constraints: const BoxConstraints(
                                minWidth: 12,
                                minHeight: 12,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$count',
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: palette.accent,
                                  fontWeight: DesignTokens.fontWeightStrong,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            SizedBox(height: gap),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    key: ValueKey('widget-calendar-date-$dayKey'),
                    width: 22,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isToday ? palette.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${value.day}',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: dateFontSize,
                        color: isToday ? Colors.white : palette.ink,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
    final palette = _ApplePreviewPalette.of(
      context,
      Theme.of(context).colorScheme,
    );
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.ink),
            ),
          ),
        ],
      ),
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

/// core 4 模块（待办/专注/习惯/月历）使用苹果风样卡；其余 5 个沿用原预览。
bool _usesApplePreview(WidgetPreviewKind kind) => switch (kind) {
  WidgetPreviewKind.todo ||
  WidgetPreviewKind.focus ||
  WidgetPreviewKind.habit ||
  WidgetPreviewKind.calendar => true,
  WidgetPreviewKind.schedule ||
  WidgetPreviewKind.goal ||
  WidgetPreviewKind.course ||
  WidgetPreviewKind.note ||
  WidgetPreviewKind.anniversary => false,
};

/// 卡片头栏与底栏共用的模块名：优先品牌词，独立预览回退到 I18n 导航词。
List<String> _appleNavLabels(ThemeProvider? themeProvider) {
  final strings = themeProvider?.brand.strings;
  return <String>[
    strings?.navTodo ?? I18n.tr('nav.todo'),
    strings?.navHabit ?? I18n.tr('nav.habit'),
    strings?.navCalendar ?? I18n.tr('nav.calendar'),
    strings?.navFocus ?? I18n.tr('nav.focus'),
  ];
}

/// 今日可见未完成待办：与主推送同口径（可见今日 → 四象限 Q1→Q3→Q2→Q4 →
/// 同象限优先级倒序/手动次序/创建时刻/ID 稳定兜底），不截 Top3。
///
/// 返回 null 表示当前没有 `TodoProvider`（独立预览/组件测试），由样卡回退到
/// 示例列表；返回空列表表示真实数据里今天确实没有待办，必须走真空态。
List<TodoItem>? _watchTodayTodos(BuildContext context, DateTime now) {
  TodoProvider? provider;
  try {
    provider = context.watch<TodoProvider>();
  } catch (_) {
    return null;
  }
  return buildHomeWidgetTodoItems(provider.visibleTodayTodos(now), now: now);
}

/// 苹果风样卡配色：浅色雾白 + 墨黑，深色 1C1C1E/2C2C2E，accent 取主题 primary。
///
/// 深色下把 primary 与白色混合抬高对比，避免品牌红在深底上发闷；
/// 浅色直接用主题 primary（默认 #C95455）。
class _ApplePreviewPalette {
  final Color surface;
  final Color ink;
  final Color secondary;
  final Color track;
  final Color selection;
  final Color accent;
  final bool isDark;

  const _ApplePreviewPalette({
    required this.surface,
    required this.ink,
    required this.secondary,
    required this.track,
    required this.selection,
    required this.accent,
    required this.isDark,
  });

  factory _ApplePreviewPalette.of(BuildContext context, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _ApplePreviewPalette(
      surface: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F8FA),
      ink: isDark ? const Color(0xFFF5F5F7) : const Color(0xFF1C1C1E),
      secondary: isDark ? const Color(0xFFB1B1B7) : const Color(0xFF6E6E73),
      track: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE9EBEF),
      selection: isDark ? const Color(0xFF48484D) : const Color(0xFFFFFFFF),
      accent: isDark ? Color.lerp(cs.primary, Colors.white, 0.32)! : cs.primary,
      isDark: isDark,
    );
  }

  /// 主题背景图片上的轻 overlay：保留图案，同时保证正文对比度。
  LinearGradient get imageOverlay => LinearGradient(
    colors: isDark
        ? [
            Colors.black.withValues(alpha: 0.42),
            surface.withValues(alpha: 0.58),
          ]
        : [surface.withValues(alpha: 0.66), surface.withValues(alpha: 0.30)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// 苹果风样卡：14dp 边距（月历 12dp）、28dp 头栏、28dp 分段底栏。
///
/// 头栏只写模块名（月历写完整月份）与真实计数，不放“预览”字样或元信息占位；
/// 外层“预览”字样只属于 App 页面上下文。
class _WidgetApplePreview extends StatelessWidget {
  final WidgetPreviewKind kind;
  final WidgetDisplayMode displayMode;
  final _ApplePreviewPalette palette;
  final List<String> navLabels;
  final DateTime today;
  final List<TodoItem>? todos;

  const _WidgetApplePreview({
    required this.kind,
    required this.displayMode,
    required this.palette,
    required this.navLabels,
    required this.today,
    required this.todos,
  });

  static const _selectedNavIndex = <WidgetPreviewKind, int>{
    WidgetPreviewKind.todo: 0,
    WidgetPreviewKind.habit: 1,
    WidgetPreviewKind.calendar: 2,
    WidgetPreviewKind.focus: 3,
  };

  int get selectedIndex => _selectedNavIndex[kind] ?? 0;

  bool get isCalendar => kind == WidgetPreviewKind.calendar;

  String get _headerLabel => navLabels[selectedIndex];

  @override
  Widget build(BuildContext context) {
    // 月历走独立的纵向月份浏览宿主：头栏是模块名 + “今天”按钮，月份标题在
    // 每个月份项内部；其余页面沿用 14dp 边距的样卡布局。
    if (isCalendar) {
      return _WidgetAppleCalendarHost(
        displayMode: displayMode,
        palette: palette,
        navLabels: navLabels,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 28, child: _buildHeader(context)),
          const SizedBox(height: 8),
          Expanded(
            child: _WidgetPreviewContentFrame(
              mode: displayMode,
              alignment: Alignment.topCenter,
              child: switch (kind) {
                WidgetPreviewKind.todo => _WidgetPreviewTodoBody(
                  todos: todos,
                  navTodoLabel: navLabels[0],
                ),
                WidgetPreviewKind.focus => const _WidgetPreviewFocusBody(),
                WidgetPreviewKind.habit => const _WidgetPreviewHabitBody(),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
          const SizedBox(height: 8),
          // core 4 任何密度都保留 4 个 tab（原生 compact 也有导航）。
          _WidgetAppleNav(
            labels: navLabels,
            selectedIndex: selectedIndex,
            palette: palette,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const WidgetBrandLogo(size: 18),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _headerLabel,
            key: const ValueKey('widget-preview-header-label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: DesignTokens.fontWeightStrong,
              color: palette.ink,
            ),
          ),
        ),
        if (kind == WidgetPreviewKind.todo)
          _buildTodoCount()
        else if (kind == WidgetPreviewKind.focus)
          Text(
            '${today.month.toString().padLeft(2, '0')}/'
            '${today.day.toString().padLeft(2, '0')}',
            maxLines: 1,
            style: TextStyle(fontSize: 11, color: palette.secondary),
          ),
      ],
    );
  }

  Widget _buildTodoCount() {
    final count = todos?.length ?? 3;
    return Row(
      key: const ValueKey('widget-preview-todo-count'),
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$count',
          maxLines: 1,
          style: TextStyle(
            fontSize: DesignTokens.fontSizeWidgetCount,
            height: 1,
            fontWeight: DesignTokens.fontWeightStrong,
            color: count == 0 ? palette.secondary : palette.accent,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          I18n.tr('widget.todo_count_unit'),
          maxLines: 1,
          style: TextStyle(fontSize: 11, color: palette.secondary),
        ),
      ],
    );
  }
}

/// 月历头栏的“今天”按钮：点按由宿主滚回本地当前月。
class _WidgetCalendarTodayButton extends StatelessWidget {
  final _ApplePreviewPalette palette;
  final VoidCallback onTap;

  const _WidgetCalendarTodayButton({
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('widget-preview-calendar-today'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: palette.track,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          I18n.tr('widget.today_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            fontWeight: DesignTokens.fontWeightStrong,
            color: palette.accent,
          ),
        ),
      ),
    );
  }
}

/// 月历样卡宿主：月份标题和今天按钮沿用原头栏，正文保留完整单月尺寸。
class _WidgetAppleCalendarHost extends StatefulWidget {
  final WidgetDisplayMode displayMode;
  final _ApplePreviewPalette palette;
  final List<String> navLabels;

  const _WidgetAppleCalendarHost({
    required this.displayMode,
    required this.palette,
    required this.navLabels,
  });

  @override
  State<_WidgetAppleCalendarHost> createState() =>
      _WidgetAppleCalendarHostState();
}

class _WidgetAppleCalendarHostState extends State<_WidgetAppleCalendarHost> {
  final GlobalKey<_WidgetPreviewCalendarBodyState> _monthsKey =
      GlobalKey<_WidgetPreviewCalendarBodyState>();

  String get _monthLabel {
    final today = AppClock.today();
    return I18n.tr('widget.calendar_month_title')
        .replaceAll('{year}', '${today.year}')
        .replaceAll('{month}', '${today.month}');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 24, child: _buildHeader()),
          const SizedBox(height: 6),
          Expanded(
            child: _WidgetPreviewContentFrame(
              mode: widget.displayMode,
              designHeightOverride: _WidgetPreviewCalendarBody.designHeightFor(
                widget.displayMode,
              ),
              alignment: Alignment.topCenter,
              child: _WidgetPreviewCalendarBody(
                key: _monthsKey,
                displayMode: widget.displayMode,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _WidgetAppleNav(
            labels: widget.navLabels,
            selectedIndex: 2,
            palette: widget.palette,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const WidgetBrandLogo(size: 18),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _monthLabel,
            key: const ValueKey('widget-preview-header-label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: DesignTokens.fontWeightStrong,
              color: widget.palette.ink,
            ),
          ),
        ),
        _WidgetCalendarTodayButton(
          palette: widget.palette,
          onTap: () => _monthsKey.currentState?.refreshCurrentMonth(),
        ),
      ],
    );
  }
}

/// 苹果风分段底栏：28dp 高、浅灰轨道、选中一段白色/深灰小圆角 + accent 文字。
class _WidgetAppleNav extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final _ApplePreviewPalette palette;

  const _WidgetAppleNav({
    required this.labels,
    required this.selectedIndex,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('widget-preview-nav-track'),
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.track,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0) const SizedBox(width: 2),
            Expanded(
              child: Container(
                key: ValueKey('widget-preview-nav-$index'),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: index == selectedIndex
                      ? palette.selection
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  labels[index],
                  key: index == selectedIndex
                      ? const ValueKey('widget-preview-nav-selected')
                      : null,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: index == selectedIndex
                        ? DesignTokens.fontWeightStrong
                        : DesignTokens.fontWeightMedium,
                    color: index == selectedIndex
                        ? palette.accent
                        : palette.secondary,
                  ),
                ),
              ),
            ),
          ],
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
