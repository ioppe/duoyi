import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import 'surface_components.dart';

class LanguageSettingsTile extends StatelessWidget {
  const LanguageSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    return AppSettingsTile(
      icon: Icons.language_outlined,
      color: Theme.of(context).colorScheme.primary,
      title: I18n.tr('settings.language'),
      subtitle: locale.followsSystem
          ? '${I18n.tr('settings.language.system')} · ${I18n.tr('settings.language.${locale.locale.storageValue}')}'
          : I18n.tr('settings.language.${locale.locale.storageValue}'),
      trailing: AppCompactDropdown<String>(
        key: const ValueKey('language-selection'),
        width: 156,
        value: locale.selection,
        items: [
          for (final value in const ['system', 'zh', 'en'])
            DropdownMenuItem(
              value: value,
              child: Text(I18n.tr('settings.language.$value')),
            ),
        ],
        onChanged: (value) {
          if (value != null) locale.setSelection(value);
        },
      ),
    );
  }
}
