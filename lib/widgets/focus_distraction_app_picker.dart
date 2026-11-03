import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../models/pomodoro.dart';
import '../services/focus_distraction_service.dart';
import 'surface_components.dart';

/// 从手机上可启动的已安装应用里勾选分心（黑名单）或无关（白名单）应用。
///
/// [initialMode] / [initialPackages] 是打开时的草稿起点；只有点击“完成”
/// 才会通过 [onDone] 落盘，返回或点遮罩都不会改变配置。
class FocusDistractionAppPicker extends StatefulWidget {
  final String initialMode;
  final List<String> initialPackages;
  final Future<List<InstalledFocusApp>> Function() loadApps;
  final Future<void> Function(String mode, List<String> packages) onDone;

  const FocusDistractionAppPicker({
    super.key,
    required this.initialMode,
    required this.initialPackages,
    required this.loadApps,
    required this.onDone,
  });

  @override
  State<FocusDistractionAppPicker> createState() =>
      _FocusDistractionAppPickerState();
}

class _FocusDistractionAppPickerState extends State<FocusDistractionAppPicker> {
  final TextEditingController _search = TextEditingController();
  late String _mode;
  late final Set<String> _selected;
  List<InstalledFocusApp>? _apps;
  String _query = '';
  bool _loadFailed = false;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _mode = PomodoroConfig.normalizeDistractionSelectionMode(
      widget.initialMode,
    );
    _selected = {
      for (final package in widget.initialPackages)
        if (package.trim().isNotEmpty) package.trim(),
    };
    unawaited(_loadApps());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await widget.loadApps();
      if (!mounted) return;
      setState(() => _apps = apps);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[FocusDistractionAppPicker] load apps failed: $e');
      setState(() {
        _apps = const <InstalledFocusApp>[];
        _loadFailed = true;
      });
    }
  }

  void _retry() {
    setState(() {
      _apps = null;
      _loadFailed = false;
    });
    unawaited(_loadApps());
  }

  List<InstalledFocusApp> _filteredApps(List<InstalledFocusApp>? apps) {
    if (apps == null) return const <InstalledFocusApp>[];
    if (_query.isEmpty) return apps;
    return apps
        .where(
          (app) =>
              app.displayLabel.toLowerCase().contains(_query) ||
              app.packageName.toLowerCase().contains(_query),
        )
        .toList(growable: false);
  }

  void _toggle(String packageName, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(packageName);
      } else {
        _selected.remove(packageName);
      }
    });
  }

  String _summary(int visibleSelected, int total) {
    final selected = I18n.tr('focus.distraction.picker.summary_selected');
    if (_mode == PomodoroConfig.distractionModeWhitelist) {
      final remaining = total - visibleSelected;
      return '$selected $visibleSelected · '
          '${I18n.tr('focus.distraction.picker.summary_remaining')} $remaining';
    }
    return '$selected $visibleSelected · '
        '${I18n.tr('focus.distraction.picker.summary_available')} $total';
  }

  String _packageLabel(InstalledFocusApp app) {
    if (!app.isSystemApp) return app.packageName;
    return '${app.packageName} · '
        '${I18n.tr('focus.distraction.picker.system_app')}';
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final packages = _selected.toList()..sort();
    try {
      await widget.onDone(_mode, packages);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      debugPrint('[FocusDistractionAppPicker] save failed: $e');
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apps = _apps;
    final filtered = _filteredApps(apps);
    final visibleSelected = apps == null
        ? 0
        : apps.where((app) => _selected.contains(app.packageName)).length;
    return AppModalSheet(
      title: I18n.tr('focus.distraction.picker.title'),
      subtitle: I18n.tr('focus.distraction.picker.subtitle'),
      actions: [
        TextButton(
          key: const ValueKey('focus_distraction_cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(I18n.tr('focus.distraction.picker.cancel')),
        ),
        FilledButton(
          key: const ValueKey('focus_distraction_done'),
          onPressed: _saving || apps == null ? null : _submit,
          child: Text(I18n.tr('focus.distraction.picker.done')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              key: const ValueKey('focus_distraction_mode'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: PomodoroConfig.distractionModeBlacklist,
                  label: Text(I18n.tr('focus.distraction.mode.blacklist')),
                ),
                ButtonSegment(
                  value: PomodoroConfig.distractionModeWhitelist,
                  label: Text(I18n.tr('focus.distraction.mode.whitelist')),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            I18n.tr(
              _mode == PomodoroConfig.distractionModeWhitelist
                  ? 'focus.distraction.mode.whitelist_hint'
                  : 'focus.distraction.mode.blacklist_hint',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceLg),
          TextField(
            key: const ValueKey('focus_distraction_search'),
            controller: _search,
            decoration: InputDecoration(
              hintText: I18n.tr('focus.distraction.picker.search'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          if (apps == null)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spaceXl,
              ),
              child: Column(
                children: [
                  const SizedBox(
                    width: DesignTokens.controlIconSize,
                    height: DesignTokens.controlIconSize,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: DesignTokens.spaceSm),
                  Text(
                    I18n.tr('focus.distraction.picker.loading'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else if (_loadFailed)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spaceLg,
              ),
              child: Column(
                children: [
                  Text(
                    I18n.tr('focus.distraction.picker.load_failed'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: DesignTokens.spaceSm),
                  TextButton(
                    key: const ValueKey('focus_distraction_retry'),
                    onPressed: _retry,
                    child: Text(I18n.tr('focus.distraction.picker.retry')),
                  ),
                ],
              ),
            )
          else if (apps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spaceXl,
              ),
              child: Text(
                I18n.tr('focus.distraction.picker.empty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            )
          else ...[
            Text(
              _summary(visibleSelected, apps.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: DesignTokens.spaceLg,
                ),
                child: Text(
                  I18n.tr('focus.distraction.picker.no_matches'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final app in filtered)
                CheckboxListTile(
                  key: ValueKey('focus_distraction_app_${app.packageName}'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.apps_outlined),
                  title: Text(app.displayLabel),
                  subtitle: Text(_packageLabel(app)),
                  value: _selected.contains(app.packageName),
                  onChanged: (checked) => _toggle(app.packageName, checked),
                ),
          ],
          if (_saveFailed) ...[
            const SizedBox(height: DesignTokens.spaceSm),
            Text(
              I18n.tr('focus.distraction.picker.save_failed'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
