import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/preferences_provider.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import 'calendar_screen.dart';
import 'habit_screen.dart';
import 'today_screen.dart';
import 'todo_screen.dart';
import 'widget_screen.dart';

class MoreApplicationsScreen extends StatelessWidget {
  final List<int>? visibleBottomNavTabs;

  const MoreApplicationsScreen({super.key, this.visibleBottomNavTabs});

  static List<MoreAppItem> hiddenBottomNavApps(
    PreferencesProvider prefs, {
    List<int>? visibleBottomNavTabs,
  }) {
    final visible = (visibleBottomNavTabs ?? prefs.visibleBottomNavTabs)
        .toSet();
    final apps = <MoreAppItem>[
      MoreAppItem(
        tab: 0,
        icon: Icons.today_outlined,
        label: '今日',
        color: Colors.blue,
        builder: (_) => const TodayScreen(),
      ),
      MoreAppItem(
        tab: 1,
        icon: Icons.checklist,
        label: '待办',
        color: Colors.green,
        builder: (_) => const TodoScreen(),
      ),
      MoreAppItem(
        tab: 2,
        icon: Icons.repeat,
        label: '习惯',
        color: Colors.teal,
        builder: (_) => const HabitScreen(),
      ),
      MoreAppItem(
        tab: 3,
        icon: Icons.calendar_month_outlined,
        label: '日历',
        color: Colors.indigo,
        builder: (_) => const CalendarScreen(),
      ),
      MoreAppItem(
        tab: 5,
        icon: Icons.widgets_outlined,
        label: '小组件',
        color: Colors.deepPurple,
        builder: (_) => const WidgetScreen(),
      ),
    ];
    return apps
        .where((app) => !visible.contains(app.tab))
        .where((app) => PreferencesProvider.isBottomNavTabSupported(app.tab))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (context.read<PreferencesProvider?>() == null) {
      return _MoreApplicationsProviderFallback(
        visibleBottomNavTabs: visibleBottomNavTabs,
      );
    }
    return _MoreApplicationsBody(visibleBottomNavTabs: visibleBottomNavTabs);
  }
}

class _MoreApplicationsProviderFallback extends StatefulWidget {
  final List<int>? visibleBottomNavTabs;

  const _MoreApplicationsProviderFallback({this.visibleBottomNavTabs});

  @override
  State<_MoreApplicationsProviderFallback> createState() =>
      _MoreApplicationsProviderFallbackState();
}

class _MoreApplicationsProviderFallbackState
    extends State<_MoreApplicationsProviderFallback> {
  late final PreferencesProvider _preferences = PreferencesProvider();

  @override
  void initState() {
    super.initState();
    unawaited(_preferences.loadFromStorage());
  }

  @override
  void dispose() {
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PreferencesProvider>.value(
      value: _preferences,
      child: _MoreApplicationsBody(
        visibleBottomNavTabs: widget.visibleBottomNavTabs,
      ),
    );
  }
}

class _MoreApplicationsBody extends StatelessWidget {
  final List<int>? visibleBottomNavTabs;

  const _MoreApplicationsBody({this.visibleBottomNavTabs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final apps = MoreApplicationsScreen.hiddenBottomNavApps(
      context.watch<PreferencesProvider>(),
      visibleBottomNavTabs: visibleBottomNavTabs,
    );
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('更多应用'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: ColoredBox(
        color: routeBackground.withValues(alpha: 0.92),
        child: SafeArea(
          top: false,
          child: AppSecondaryControlTheme(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                AppSurfaceCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '隐藏入口',
                        style: appSecondaryMenuItemTextStyle(
                          context,
                        ).copyWith(color: cs.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '显示未在当前底部导航展示的功能。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (apps.isEmpty)
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      '当前没有被隐藏的底部导航功能',
                      style: appSecondaryMenuItemTextStyle(
                        context,
                      ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : MediaQuery.sizeOf(context).width;
                      final veryNarrow = width < 280;
                      final compact = width < 520;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: veryNarrow
                            ? 1
                            : compact
                            ? 2
                            : 3,
                        childAspectRatio: veryNarrow
                            ? 3.0
                            : compact
                            ? 2.55
                            : 3.3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        children: [
                          for (final app in apps)
                            MoreApplicationButton(app: app),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MoreAppItem {
  final int tab;
  final IconData icon;
  final String label;
  final Color color;
  final WidgetBuilder builder;

  const MoreAppItem({
    required this.tab,
    required this.icon,
    required this.label,
    required this.color,
    required this.builder,
  });
}

class MoreApplicationButton extends StatelessWidget {
  final MoreAppItem app;

  const MoreApplicationButton({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('more_application_button_tap_region'),
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (routeContext) =>
                  BrandRouteSurface(child: app.builder(routeContext)),
            ),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.64),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.12),
              width: 0.45,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: app.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(app.icon, color: app.color, size: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appSecondaryMenuItemTextStyle(
                      context,
                    ).copyWith(color: cs.onSurface),
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
