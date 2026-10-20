import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/page_tab_style.dart';

/// One treatment for page navigation; filters and form choices remain controls.
class AppPageTabs extends StatelessWidget implements PreferredSizeWidget {
  final List<Widget> tabs;
  final TabController? controller;
  final ValueChanged<int>? onTap;
  final Key? barKey;
  final double height;
  final EdgeInsetsGeometry padding;

  const AppPageTabs({
    super.key,
    required this.tabs,
    this.controller,
    this.onTap,
    this.barKey,
    this.height = DesignTokens.controlMinHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: DesignTokens.spaceMd),
  });

  static double heightFor(BuildContext context) => math.max(
    DesignTokens.controlMinHeight,
    MediaQuery.textScalerOf(context).scale(DesignTokens.fontSizeBody) * 1.5 +
        DesignTokens.spaceMd,
  );

  @override
  Size get preferredSize => Size.fromHeight(height + DesignTokens.spaceXxs);

  @override
  Widget build(BuildContext context) {
    final style = appPageTabTheme(Theme.of(context));
    return Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: TabBar(
        key: barKey,
        controller: controller,
        onTap: onTap,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: padding,
        labelPadding: style.labelPadding,
        dividerColor: style.dividerColor,
        indicatorSize: style.indicatorSize,
        indicator: style.indicator,
        labelColor: style.labelColor,
        unselectedLabelColor: style.unselectedLabelColor,
        labelStyle: style.labelStyle,
        unselectedLabelStyle: style.unselectedLabelStyle,
        overlayColor: style.overlayColor,
        tabs: [
          for (final tab in tabs)
            if (tab is Tab)
              Tab(
                key: tab.key,
                height: height,
                text: tab.text,
                icon: tab.icon,
                iconMargin: tab.iconMargin,
                child: tab.child,
              )
            else
              Tab(height: height, child: tab),
        ],
      ),
    );
  }
}

class AppPageOption<T> {
  final T value;
  final String text;

  const AppPageOption({required this.value, required this.text});
}

/// Adapts value-based page views to the same tabs as TabBarView screens.
class AppPageSwitcher<T> extends StatefulWidget {
  final List<AppPageOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const AppPageSwitcher({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  }) : assert(options.length > 1);

  @override
  State<AppPageSwitcher<T>> createState() => _AppPageSwitcherState<T>();
}

class _AppPageSwitcherState<T> extends State<AppPageSwitcher<T>>
    with TickerProviderStateMixin {
  late TabController _controller;

  int get _index =>
      widget.options.indexWhere((item) => item.value == widget.value);

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: widget.options.length,
      initialIndex: _index,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant AppPageSwitcher<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      _controller.dispose();
      _controller = TabController(
        length: widget.options.length,
        initialIndex: _index,
        vsync: this,
      );
    } else if (_controller.index != _index) {
      _controller.index = _index;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPageTabs(
    controller: _controller,
    height: AppPageTabs.heightFor(context),
    padding: EdgeInsets.zero,
    onTap: (index) => widget.onChanged(widget.options[index].value),
    tabs: [for (final option in widget.options) Tab(text: option.text)],
  );
}
