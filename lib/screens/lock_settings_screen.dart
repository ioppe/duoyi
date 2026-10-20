import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/app_lock_provider.dart';
import '../widgets/surface_components.dart';

class LockSettingsScreen extends StatefulWidget {
  const LockSettingsScreen({super.key});

  @override
  State<LockSettingsScreen> createState() => _LockSettingsScreenState();
}

class _LockSettingsScreenState extends State<LockSettingsScreen> {
  Future<void> _setPinFlow() async {
    final messenger = ScaffoldMessenger.of(context);
    final lock = context.read<AppLockProvider>();
    final pin = await _askPin(I18n.tr('app_lock.dialog.set_pin'));
    if (pin == null) return;
    final confirm = await _askPin(I18n.tr('app_lock.dialog.confirm_pin'));
    if (confirm == null) return;
    if (pin != confirm) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.tr('app_lock.pin_mismatch'))),
      );
      return;
    }
    final ok = await lock.setPin(pin);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? I18n.tr('app_lock.enabled_message')
              : I18n.tr('app_lock.pin_invalid'),
        ),
      ),
    );
  }

  Future<void> _disableFlow() async {
    final messenger = ScaffoldMessenger.of(context);
    final lock = context.read<AppLockProvider>();
    final pin = await _askPin(I18n.tr('app_lock.dialog.disable_pin'));
    if (pin == null) return;
    final ok = await lock.verify(pin);
    if (!ok) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.tr('app_lock.pin_wrong'))),
      );
      return;
    }
    await lock.disable(pin);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(I18n.tr('app_lock.disabled_message'))),
    );
  }

  Future<String?> _askPin(String title) async {
    final ctrl = TextEditingController();
    try {
      final v = await showDialog<String>(
        context: context,
        builder: (ctx) => AppDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: true,
            maxLength: 8,
            decoration: InputDecoration(
              hintText: I18n.tr('app_lock.pin_hint'),
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(I18n.tr('action.confirm')),
            ),
          ],
        ),
      );
      if (v == null) return null;
      if (!RegExp(r'^\d{4,8}$').hasMatch(v)) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('app_lock.pin_invalid'))),
        );
        return null;
      }
      return v;
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('app_lock.title')),
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
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.lock_outline,
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
                          I18n.tr('app_lock.hero.title'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: DesignTokens.fontWeightStrong,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          I18n.tr('app_lock.hero.subtitle'),
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
              title: I18n.tr('app_lock.section.status'),
              subtitle: I18n.tr('app_lock.section.status.subtitle'),
              children: [
                AppSwitchTile(
                  icon: lock.enabled ? Icons.lock : Icons.lock_open,
                  color: lock.enabled ? Colors.green : Colors.orange,
                  title: I18n.tr('app_lock.enable'),
                  subtitle: lock.enabled
                      ? I18n.tr('app_lock.enabled')
                      : I18n.tr('app_lock.disabled.subtitle'),
                  value: lock.enabled,
                  onChanged: (enabled) =>
                      enabled ? _setPinFlow() : _disableFlow(),
                ),
                if (lock.enabled) ...[
                  AppSettingsTile(
                    icon: Icons.password,
                    color: cs.primary,
                    title: I18n.tr('app_lock.change_pin'),
                    subtitle: I18n.tr('app_lock.change_pin.subtitle'),
                    onTap: _setPinFlow,
                  ),
                  AppSettingsTile(
                    icon: Icons.timer_outlined,
                    color: Colors.orange,
                    title: I18n.tr('app_lock.auto_lock'),
                    subtitle: lock.autoLockMinutes == 0
                        ? I18n.tr('app_lock.auto_lock.every_foreground')
                        : '${I18n.tr('app_lock.auto_lock.after_prefix')}'
                              '${lock.autoLockMinutes}'
                              '${I18n.tr('app_lock.auto_lock.after_suffix')}',
                    trailing: AppCompactDropdown<int>(
                      width: 132,
                      value: lock.autoLockMinutes,
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(I18n.tr('app_lock.auto_lock.immediate')),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text(
                            '1${I18n.tr('app_lock.auto_lock.minute_label')}',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 5,
                          child: Text(
                            '5${I18n.tr('app_lock.auto_lock.minute_label')}',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 15,
                          child: Text(
                            '15${I18n.tr('app_lock.auto_lock.minute_label')}',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 60,
                          child: Text(I18n.tr('app_lock.auto_lock.one_hour')),
                        ),
                        DropdownMenuItem(
                          value: 240,
                          child: Text(I18n.tr('app_lock.auto_lock.four_hours')),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          context.read<AppLockProvider>().setAutoLockMinutes(v);
                        }
                      },
                    ),
                  ),
                  AppSettingsTile(
                    icon: Icons.lock_clock_outlined,
                    color: Colors.red,
                    title: I18n.tr('app_lock.lock_now'),
                    subtitle: I18n.tr('app_lock.lock_now.subtitle'),
                    onTap: () {
                      context.read<AppLockProvider>().lock();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            AppSurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      I18n.tr('app_lock.tip'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.68),
                        height: 1.45,
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
