import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/platform_info.dart';
import '../core/pomodoro_floating_window_size.dart';
import '../core/app_clock.dart';
import '../core/app_motion.dart';
import '../core/i18n_date_format.dart';
import '../providers/preferences_provider.dart';
import '../widgets/surface_components.dart';
import '../widgets/language_settings_tile.dart';

/// 个性设置入口页。这里只做二级入口，不直接承载具体设置项。
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    context.watch<LocaleProvider>();
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('preferences.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.tune, color: cs.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          I18n.tr('preferences.local.title'),
                          style: appSecondaryMenuItemTextStyle(
                            context,
                          ).copyWith(color: cs.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          I18n.tr('preferences.entry.description'),
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
            AppSettingsSection(
              title: I18n.tr('preferences.entry.title'),
              subtitle: I18n.tr('preferences.entry.subtitle'),
              children: [
                AppSettingsTile(
                  icon: Icons.tune_outlined,
                  color: cs.primary,
                  title: I18n.tr('preferences.display.title'),
                  subtitle: I18n.tr('preferences.display.subtitle'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PersonalizationSettingsScreen(),
                    ),
                  ),
                ),
                AppSettingsTile(
                  icon: Icons.space_dashboard_outlined,
                  color: Colors.blueGrey,
                  title: I18n.tr('preferences.navigation.title'),
                  subtitle: _bottomNavSettingsSubtitle(),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BottomNavSettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 纯本地的用户习惯，与服务器/管理员配置无关。
class PersonalizationSettingsScreen extends StatefulWidget {
  const PersonalizationSettingsScreen({super.key});

  @override
  State<PersonalizationSettingsScreen> createState() =>
      _PersonalizationSettingsScreenState();
}

class _PersonalizationSettingsScreenState
    extends State<PersonalizationSettingsScreen> {
  final GlobalKey _dateSectionKey = GlobalKey();
  final GlobalKey _defaultsSectionKey = GlobalKey();
  final GlobalKey _interactionSectionKey = GlobalKey();
  final GlobalKey _archiveSectionKey = GlobalKey();

  static const _dateFormats = [
    ['yyyy-MM-dd', '2026-05-07'],
    ['MM/dd/yyyy', '05/07/2026'],
    ['dd/MM/yyyy', '07/05/2026'],
    ['yyyy年M月d日', '2026年5月7日'],
  ];
  static const _timeZones = [
    ['system', 'preferences.timezone.follow_system'],
    ['Asia/Shanghai', 'preferences.timezone.shanghai'],
    ['America/Mexico_City', 'preferences.timezone.mexico'],
    ['America/Tijuana', 'preferences.timezone.tijuana'],
    ['Asia/Tokyo', 'preferences.timezone.tokyo'],
    ['Asia/Hong_Kong', 'preferences.timezone.hong_kong'],
    ['Asia/Singapore', 'preferences.timezone.singapore'],
    ['America/New_York', 'preferences.timezone.new_york'],
    ['America/Los_Angeles', 'preferences.timezone.los_angeles'],
    ['Europe/London', 'preferences.timezone.london'],
    ['Europe/Paris', 'preferences.timezone.paris'],
    ['Australia/Sydney', 'preferences.timezone.sydney'],
    ['UTC', 'preferences.timezone.utc'],
  ];

  void _scrollToContext(BuildContext target) {
    Scrollable.ensureVisible(
      target,
      duration: AppMotion.transition(context),
      curve: AppMotion.enterCurve,
      alignment: 0.04,
    );
  }

  void _scrollToMenuTarget(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    _scrollToContext(target);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PreferencesProvider>();
    context.watch<LocaleProvider>();
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('preferences.display.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.tune, color: cs.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          I18n.tr('preferences.local.title'),
                          style: appSecondaryMenuItemTextStyle(
                            context,
                          ).copyWith(color: cs.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          I18n.tr('preferences.local.subtitle'),
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
            _PreferenceSectionMenu(
              groups: [
                _PreferenceMenuGroup(
                  title: I18n.tr('preferences.menu.display'),
                  items: [
                    _PreferenceMenuItem(
                      icon: Icons.calendar_month_outlined,
                      label: I18n.tr('preferences.menu.calendar'),
                      onTap: () => _scrollToMenuTarget(_dateSectionKey),
                    ),
                    _PreferenceMenuItem(
                      icon: Icons.tune_outlined,
                      label: I18n.tr('preferences.section.defaults'),
                      onTap: () => _scrollToMenuTarget(_defaultsSectionKey),
                    ),
                    _PreferenceMenuItem(
                      icon: Icons.touch_app_outlined,
                      label: I18n.tr('preferences.menu.interaction_archive'),
                      onTap: () => _scrollToMenuTarget(_interactionSectionKey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _dateSectionKey,
              child: AppSettingsSection(
                title: I18n.tr('preferences.section.date'),
                subtitle: I18n.tr('preferences.section.date.subtitle'),
                children: [
                  const LanguageSettingsTile(),
                  AppSwitchTile(
                    key: const ValueKey('preferences_home_calendar_switch'),
                    icon: Icons.calendar_today_outlined,
                    color: cs.primary,
                    value: p.showHomeCalendar,
                    title: I18n.tr('preferences.home_calendar.title'),
                    subtitle: I18n.tr('preferences.home_calendar.subtitle'),
                    onChanged: p.setShowHomeCalendar,
                  ),
                  AppSettingsTile(
                    icon: Icons.calendar_view_week_outlined,
                    color: cs.primary,
                    title: I18n.tr('preferences.first_day.title'),
                    subtitle: p.firstDayOfWeek == 1
                        ? I18n.tr('preferences.first_day.current_monday')
                        : I18n.tr('preferences.first_day.current_sunday'),
                    trailing: _compactDropdown<int>(
                      value: p.firstDayOfWeek,
                      items: [
                        DropdownMenuItem(
                          value: 1,
                          child: Text(
                            I18n.tr('weekday.mon'),
                            style: appSecondaryControlTextStyle(context),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 7,
                          child: Text(
                            I18n.tr('weekday.sun'),
                            style: appSecondaryControlTextStyle(context),
                          ),
                        ),
                      ],
                      onChanged: (v) => v == null
                          ? null
                          : context
                                .read<PreferencesProvider>()
                                .setFirstDayOfWeek(v),
                    ),
                  ),
                  AppSettingsTile(
                    icon: Icons.date_range_outlined,
                    color: Colors.teal,
                    title: I18n.tr('preferences.date_format.title'),
                    subtitle: _dateFormats.firstWhere(
                      (f) => f[0] == p.dateFormat,
                      orElse: () => _dateFormats.first,
                    )[1],
                    trailing: _compactDropdown<String>(
                      width: 156,
                      value: p.dateFormat,
                      items: [
                        for (final f in _dateFormats)
                          DropdownMenuItem(
                            value: f[0],
                            child: Text(
                              f[1],
                              style: appSecondaryControlTextStyle(context),
                            ),
                          ),
                      ],
                      onChanged: (v) => v == null
                          ? null
                          : context.read<PreferencesProvider>().setDateFormat(
                              v,
                            ),
                    ),
                  ),
                  AppSettingsTile(
                    icon: Icons.public_outlined,
                    color: Colors.deepOrange,
                    title: I18n.tr('preferences.timezone.title'),
                    subtitle:
                        '${p.followSystemTimeZone ? '${I18n.tr('preferences.timezone.follow_system')} · ' : ''}${p.appTimeZone}\n${I18nDateFormat.fullDateTime(AppClock.now())}\n${I18n.tr('preferences.timezone.scope')}',
                    trailing: _compactDropdown<String>(
                      width: 156,
                      value: p.appTimeZoneSelection,
                      items: [
                        for (final z in _timeZones)
                          DropdownMenuItem(
                            value: z[0],
                            child: Text(
                              I18n.tr(z[1]),
                              style: appSecondaryControlTextStyle(context),
                            ),
                          ),
                      ],
                      onChanged: (v) => v == null
                          ? null
                          : context.read<PreferencesProvider>().setAppTimeZone(
                              v,
                            ),
                    ),
                  ),
                  AppSwitchTile(
                    icon: Icons.brightness_2_outlined,
                    color: Colors.indigo,
                    value: p.showLunar,
                    title: I18n.tr('preferences.lunar.title'),
                    subtitle: I18n.tr('preferences.lunar.subtitle'),
                    onChanged: (v) =>
                        context.read<PreferencesProvider>().setShowLunar(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _defaultsSectionKey,
              child: AppSettingsSection(
                title: I18n.tr('preferences.section.defaults'),
                subtitle: I18n.tr('preferences.section.defaults.subtitle'),
                children: [
                  AppSettingsTile(
                    icon: Icons.open_in_new,
                    color: Colors.blue,
                    title: I18n.tr('preferences.default_tab.title'),
                    subtitle: _tabLabel(p.defaultTab),
                    trailing: _compactDropdown<int>(
                      value: p.defaultTab,
                      items: [
                        for (var tab = 0; tab <= 6; tab++)
                          if (PreferencesProvider.isBottomNavTabSupported(tab))
                            DropdownMenuItem(
                              value: tab,
                              child: Text(
                                _tabLabel(tab),
                                style: appSecondaryControlTextStyle(context),
                              ),
                            ),
                      ],
                      onChanged: (v) => v == null
                          ? null
                          : context.read<PreferencesProvider>().setDefaultTab(
                              v,
                            ),
                    ),
                  ),
                  AppSwitchTile(
                    icon: Icons.add_circle_outline,
                    color: cs.primary,
                    value: p.quickCaptureFab,
                    title: I18n.tr('preferences.quick_capture.title'),
                    subtitle: I18n.tr('preferences.quick_capture.subtitle'),
                    onChanged: (v) => context
                        .read<PreferencesProvider>()
                        .setQuickCaptureFab(v),
                  ),
                  AppSwitchTile(
                    icon: Icons.done_all,
                    color: Colors.green,
                    value: p.showCompletedTodos,
                    title: I18n.tr('preferences.show_completed.title'),
                    subtitle: I18n.tr('preferences.show_completed.subtitle'),
                    onChanged: (v) => context
                        .read<PreferencesProvider>()
                        .setShowCompletedTodos(v),
                  ),
                  _SliderSetting(
                    icon: Icons.timer_outlined,
                    color: Colors.red,
                    title: I18n.tr('preferences.pomodoro_length.title'),
                    subtitle:
                        '${p.defaultPomodoroMinutes} ${I18n.tr('unit.minute')}',
                    value: p.defaultPomodoroMinutes.toDouble(),
                    min: 5,
                    max: 90,
                    divisions: 17,
                    label: '${p.defaultPomodoroMinutes} ${I18n.tr('unit.min')}',
                    onChanged: (v) => context
                        .read<PreferencesProvider>()
                        .setDefaultPomodoroMinutes(v.toInt()),
                  ),
                  // 悬浮窗只存在于 macOS；其他平台不显示这个设备本地偏好。
                  if (PlatformInfo.isMacOS)
                    AppSettingsTile(
                      icon: Icons.picture_in_picture_alt_outlined,
                      color: Colors.deepPurple,
                      title: I18n.tr('preferences.floating_window.size'),
                      subtitle: I18n.tr('preferences.floating_window.subtitle'),
                      trailing: _compactDropdown<PomodoroFloatingWindowSize>(
                        value: p.pomodoroFloatingWindowSize,
                        items: [
                          for (final size in PomodoroFloatingWindowSize.values)
                            DropdownMenuItem(
                              value: size,
                              child: Text(
                                _floatingWindowSizeLabel(size),
                                style: appSecondaryControlTextStyle(context),
                              ),
                            ),
                        ],
                        onChanged: (v) => v == null
                            ? null
                            : context
                                  .read<PreferencesProvider>()
                                  .setPomodoroFloatingWindowSize(v),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _interactionSectionKey,
              child: Column(
                children: [
                  AppSettingsSection(
                    title: I18n.tr('preferences.section.interaction'),
                    subtitle: I18n.tr(
                      'preferences.section.interaction.subtitle',
                    ),
                    children: [
                      AppSwitchTile(
                        icon: Icons.vibration,
                        color: Colors.purple,
                        value: p.haptic,
                        title: I18n.tr('preferences.haptic.title'),
                        subtitle: I18n.tr('preferences.haptic.subtitle'),
                        onChanged: (v) =>
                            context.read<PreferencesProvider>().setHaptic(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _archiveSectionKey,
                    child: AppSettingsSection(
                      title: I18n.tr('preferences.section.auto_archive'),
                      subtitle: I18n.tr(
                        'preferences.section.auto_archive.subtitle',
                      ),
                      children: [
                        _SliderSetting(
                          icon: Icons.inventory_2_outlined,
                          color: Colors.brown,
                          title: I18n.tr('preferences.auto_archive.title'),
                          subtitle: p.autoArchiveCompletedDays == 0
                              ? I18n.tr('preferences.auto_archive.never')
                              : '${p.autoArchiveCompletedDays} ${I18n.tr('preferences.auto_archive.after_days')}',
                          value: p.autoArchiveCompletedDays.toDouble(),
                          min: 0,
                          max: 30,
                          divisions: 30,
                          label: p.autoArchiveCompletedDays == 0
                              ? I18n.tr('action.off')
                              : '${p.autoArchiveCompletedDays} ${I18n.tr('unit.day')}',
                          onChanged: (v) => context
                              .read<PreferencesProvider>()
                              .setAutoArchiveCompletedDays(v.toInt()),
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
  }

  Widget _compactDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double width = 156,
  }) {
    return AppCompactDropdown<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      width: width,
    );
  }

  String _floatingWindowSizeLabel(PomodoroFloatingWindowSize size) {
    return switch (size) {
      PomodoroFloatingWindowSize.large => I18n.tr(
        'preferences.floating_window.large',
      ),
      PomodoroFloatingWindowSize.compact => I18n.tr(
        'preferences.floating_window.compact',
      ),
    };
  }
}

class BottomNavSettingsScreen extends StatelessWidget {
  const BottomNavSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('preferences.section.bottom_nav')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            AppInfoBanner(
              icon: Icons.space_dashboard_outlined,
              title: I18n.tr('preferences.section.bottom_nav'),
              message: '底部导航最多显示 5 个入口，我的固定显示；小组件可以隐藏，隐藏入口会出现在我的“更多应用”。',
              color: cs.primary,
              margin: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            const _BottomNavSettingsSection(),
          ],
        ),
      ),
    );
  }
}

class _BottomNavSettingsSection extends StatelessWidget {
  const _BottomNavSettingsSection();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PreferencesProvider>();
    final tabs = p.bottomNavOrder
        .where(PreferencesProvider.isBottomNavTabSupported)
        .toList(growable: false);
    return AppSettingsSection(
      title: I18n.tr('preferences.section.bottom_nav'),
      subtitle: _bottomNavSettingsSubtitle(),
      children: [
        for (final tab in tabs)
          _NavConfigTile(
            tab: tab,
            label: _tabLabel(tab),
            visible: p.bottomNavVisible.contains(tab),
            canMoveUp: p.bottomNavOrder.indexOf(tab) > 0,
            canMoveDown:
                p.bottomNavOrder.indexOf(tab) < p.bottomNavOrder.length - 1,
          ),
      ],
    );
  }
}

String _tabLabel(int index) {
  switch (index) {
    case 0:
      return I18n.tr('nav.today');
    case 1:
      return I18n.tr('nav.todo');
    case 2:
      return I18n.tr('nav.habit');
    case 3:
      return I18n.tr('nav.calendar');
    case 4:
      return I18n.tr('nav.focus');
    case 5:
      return I18n.tr('nav.widget');
    case 6:
      return I18n.tr('nav.mine');
    default:
      return I18n.tr('nav.today');
  }
}

class _PreferenceMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PreferenceMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _PreferenceMenuGroup {
  final String title;
  final List<_PreferenceMenuItem> items;

  const _PreferenceMenuGroup({required this.title, required this.items});
}

class _PreferenceSectionMenu extends StatelessWidget {
  final List<_PreferenceMenuGroup> groups;

  const _PreferenceSectionMenu({required this.groups});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups) ...[
            Text(
              group.title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: DesignTokens.fontSizeSecondary,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: DesignTokens.spaceSm,
                runSpacing: DesignTokens.spaceSm,
                children: [
                  for (final item in group.items)
                    SizedBox(
                      width: constraints.maxWidth.clamp(0.0, 180.0),
                      child: OutlinedButton.icon(
                        icon: Icon(
                          item.icon,
                          size: DesignTokens.controlIconSize,
                        ),
                        label: Text(item.label),
                        onPressed: item.onTap,
                      ),
                    ),
                ],
              ),
            ),
            if (group != groups.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _NavConfigTile extends StatelessWidget {
  final int tab;
  final String label;
  final bool visible;
  final bool canMoveUp;
  final bool canMoveDown;

  const _NavConfigTile({
    required this.tab,
    required this.label,
    required this.visible,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  IconData get _icon => switch (tab) {
    0 => Icons.today_outlined,
    1 => Icons.checklist,
    2 => Icons.repeat,
    3 => Icons.calendar_month_outlined,
    4 => Icons.timer_outlined,
    5 => Icons.widgets_outlined,
    _ => Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    final lockedVisible = PreferencesProvider.fixedBottomNavTabs.contains(tab);
    final p = context.watch<PreferencesProvider>();
    final visibleCount = p.bottomNavVisible.length;
    final reachedLimit =
        !visible && visibleCount >= PreferencesProvider.maxBottomNavTabs;
    return AppSettingsTile(
      icon: _icon,
      color: Theme.of(context).colorScheme.primary,
      title: label,
      subtitle: lockedVisible
          ? I18n.tr('preferences.nav.fixed')
          : reachedLimit
          ? '最多显示 ${PreferencesProvider.maxBottomNavTabs} 个入口'
          : visible
          ? I18n.tr('preferences.nav.visible')
          : I18n.tr('preferences.nav.hidden'),
      trailing: _NavConfigActions(
        tab: tab,
        visible: visible,
        lockedVisible: lockedVisible,
        reachedLimit: reachedLimit,
        canMoveUp: canMoveUp,
        canMoveDown: canMoveDown,
      ),
    );
  }
}

class _NavConfigActions extends StatelessWidget {
  final int tab;
  final bool visible;
  final bool lockedVisible;
  final bool reachedLimit;
  final bool canMoveUp;
  final bool canMoveDown;

  const _NavConfigActions({
    required this.tab,
    required this.visible,
    required this.lockedVisible,
    required this.reachedLimit,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    Widget compactIconButton({
      required String tooltip,
      required VoidCallback? onPressed,
      required IconData icon,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: DesignTokens.controlIconSize),
        visualDensity: VisualDensity.standard,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: DesignTokens.controlMinHeight,
          height: DesignTokens.controlMinHeight,
        ),
      );
    }

    return SizedBox(
      key: ValueKey('bottom_nav_actions_$tab'),
      width: kMinInteractiveDimension * 2 + 56,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          compactIconButton(
            tooltip: I18n.tr('action.move_up'),
            onPressed: canMoveUp
                ? () => context.read<PreferencesProvider>().moveBottomNavTab(
                    tab,
                    -1,
                  )
                : null,
            icon: Icons.keyboard_arrow_up_rounded,
          ),
          compactIconButton(
            tooltip: I18n.tr('action.move_down'),
            onPressed: canMoveDown
                ? () => context.read<PreferencesProvider>().moveBottomNavTab(
                    tab,
                    1,
                  )
                : null,
            icon: Icons.keyboard_arrow_down_rounded,
          ),
          SizedBox(
            width: 56,
            child: Align(
              alignment: Alignment.centerRight,
              child: Switch(
                value: visible,
                onChanged: lockedVisible || reachedLimit
                    ? null
                    : (v) => context
                          .read<PreferencesProvider>()
                          .setBottomNavVisible(tab, v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  const _SliderSetting({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: DesignTokens.fontSizeSecondary,
                    fontWeight: DesignTokens.fontWeightMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

String _bottomNavSettingsSubtitle() => I18n.tr(
  PreferencesProvider.isBottomNavTabSupported(5)
      ? 'preferences.section.bottom_nav.subtitle'
      : 'preferences.nav.web.subtitle',
);
