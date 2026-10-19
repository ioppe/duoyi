import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/account_local_data_cleaner.dart';

import '../core/app_brand.dart';
import '../core/i18n.dart';
import '../providers/theme_provider.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';

class ThemePickerScreen extends StatelessWidget {
  const ThemePickerScreen({super.key});

  Color _accentColor(AppBrand brand) {
    return brand.theme.colorScheme.primary;
  }

  String _styleDescription(BrandStyle style) {
    switch (style) {
      case BrandStyle.defaultBrand:
        return I18n.tr('theme.style.default.description');
      case BrandStyle.re0:
        return I18n.tr('theme.style.re0.description');
      case BrandStyle.genshin:
        return I18n.tr('theme.style.genshin.description');
      case BrandStyle.starRail:
        return I18n.tr('theme.style.star_rail.description');
      case BrandStyle.wuthering:
        return I18n.tr('theme.style.wuthering.description');
      case BrandStyle.zzz:
        return I18n.tr('theme.style.zzz.description');
      case BrandStyle.yanyun:
        return I18n.tr('theme.style.yanyun.description');
      case BrandStyle.botw:
        return I18n.tr('theme.style.botw.description');
      case BrandStyle.liquidGlass:
        return I18n.tr('theme.style.liquid_glass.description');
    }
  }

  String _styleName(AppBrand brand) {
    return switch (brand.style) {
      BrandStyle.defaultBrand => I18n.tr('theme.style.default.name'),
      BrandStyle.re0 => I18n.tr('theme.style.re0.name'),
      BrandStyle.genshin => I18n.tr('theme.style.genshin.name'),
      BrandStyle.starRail => I18n.tr('theme.style.star_rail.name'),
      BrandStyle.wuthering => I18n.tr('theme.style.wuthering.name'),
      BrandStyle.zzz => I18n.tr('theme.style.zzz.name'),
      BrandStyle.yanyun => I18n.tr('theme.style.yanyun.name'),
      BrandStyle.botw => I18n.tr('theme.style.botw.name'),
      BrandStyle.liquidGlass => I18n.tr('theme.style.liquid_glass.name'),
    };
  }

  Widget _swatch(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Future<void> _applyThemeShopItem(
    BuildContext context, {
    required String label,
    required Future<bool> Function() applyLocal,
  }) async {
    final guest = !(context.read<AuthProvider?>()?.state.isLoggedIn ?? false);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final ok = await applyLocal();
    if (!context.mounted || !ok) return;
    if (guest &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      final prefs = await SharedPreferences.getInstance();
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      await prefs.setBool(
        AccountLocalDataCleaner.guestAppearanceMarkerKey,
        true,
      );
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          I18n.tr('appearance.applied_message').replaceAll('{name}', label),
        ),
      ),
    );
  }

  Future<void> _handleBrandTap(
    BuildContext context,
    ThemeProvider provider,
    AppBrand brand,
  ) => _applyThemeShopItem(
    context,
    label: _styleName(brand),
    applyLocal: () => provider.setBrand(brand.id),
  );

  Future<void> _handleFocusBackdropTap(
    BuildContext context,
    ThemeProvider provider,
    FocusBackdropReward backdrop,
  ) => _applyThemeShopItem(
    context,
    label: backdrop.name,
    applyLocal: () => provider.setFocusBackdrop(backdrop.id),
  );

  Future<void> _handleAvatarFrameTap(
    BuildContext context,
    ThemeProvider provider,
    AvatarFrameReward frame,
  ) => _applyThemeShopItem(
    context,
    label: frame.name,
    applyLocal: () => provider.setAvatarFrame(frame.id),
  );

  Future<void> _handleCardSkinTap(
    BuildContext context,
    ThemeProvider provider,
    CardSkinReward skin,
  ) => _applyThemeShopItem(
    context,
    label: skin.name,
    applyLocal: () => provider.setCardSkin(skin.id),
  );

  Future<void> _handleWidgetBackgroundTap(
    BuildContext context,
    ThemeProvider provider,
    String id,
    String label,
  ) => _applyThemeShopItem(
    context,
    label: label,
    applyLocal: () => provider.setWidgetBackgroundBrand(id),
  );

  Future<void> _handleWidgetCardSkinTap(
    BuildContext context,
    ThemeProvider provider,
    String id,
    String label,
  ) => _applyThemeShopItem(
    context,
    label: label,
    applyLocal: () => provider.setWidgetCardSkin(id),
  );

  Widget _applyIndicator(BuildContext context, bool isActive, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Icon(
          isActive ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isActive
              ? accent
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          I18n.tr(isActive ? 'appearance.applied' : 'appearance.apply'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _focusBackdropPreview(FocusBackdropReward backdrop) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: backdrop.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(backdrop.icon, color: Colors.white, size: 26),
    );
  }

  Widget _avatarFramePreview(AvatarFrameReward frame, ColorScheme cs) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: frame.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CircleAvatar(
        backgroundColor: cs.surface,
        child: Icon(frame.icon, color: frame.colors.first, size: 24),
      ),
    );
  }

  Widget _cardSkinPreview(CardSkinReward skin, ColorScheme cs) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: skin.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Icon(skin.icon, color: cs.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }

  Widget _widgetThemeChoice({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: appSecondaryMenuItemTextStyle(
        context,
      ).copyWith(color: selected ? cs.onSurface : cs.onSurfaceVariant),
      selectedColor: Color.alphaBlend(
        cs.primary.withValues(alpha: 0.11),
        cs.surface,
      ),
      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.42),
      side: BorderSide(
        color: selected
            ? cs.primary.withValues(alpha: 0.24)
            : cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.45,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _widgetThemeSection(BuildContext context, ThemeProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final availableBrands = provider.brands;
    final availableSkins = provider.cardSkins;
    final backgroundChoices = <({String id, String label})>[
      (id: ThemeProvider.widgetFollowThemeId, label: '跟随当前主题'),
      for (final brand in availableBrands)
        (id: brand.id, label: _styleName(brand)),
    ];
    final cardSkinChoices = <({String id, String label})>[
      (id: ThemeProvider.widgetFollowCardSkinId, label: '跟随卡片皮肤'),
      for (final skin in availableSkins) (id: skin.id, label: skin.name),
    ];

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.widgets_outlined,
                  color: cs.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '桌面小组件主题',
                      style: appSecondaryRouteTitleTextStyle(
                        context,
                      ).copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '单独调整桌面小组件背景和卡片皮肤',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '背景图',
            style: appSecondaryControlTextStyle(
              context,
            ).copyWith(color: cs.onSurface.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in backgroundChoices)
                _widgetThemeChoice(
                  context: context,
                  label: item.label,
                  selected: provider.activeWidgetBackgroundId == item.id,
                  onTap: () => _handleWidgetBackgroundTap(
                    context,
                    provider,
                    item.id,
                    item.label,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '卡片皮肤',
            style: appSecondaryControlTextStyle(
              context,
            ).copyWith(color: cs.onSurface.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in cardSkinChoices)
                _widgetThemeChoice(
                  context: context,
                  label: item.label,
                  selected: provider.activeWidgetCardSkinId == item.id,
                  onTap: () => _handleWidgetCardSkinTap(
                    context,
                    provider,
                    item.id,
                    item.label,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final currentBrand = themeProvider.brand;
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('appearance.title')),
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
                      Icons.palette_outlined,
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
                          _styleName(currentBrand),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.normal,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _styleDescription(currentBrand.style),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.66),
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          I18n.tr('appearance.free'),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppSectionHeader(
              title: I18n.tr('theme.section.styles'),
              subtitle: I18n.tr('appearance.subtitle'),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            ...themeProvider.brands.map((brand) {
              final isActive = brand.style == currentBrand.style;
              final accent = _accentColor(brand);
              return AppSurfaceCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                color: isActive ? accent.withValues(alpha: 0.08) : null,
                border: Border.all(
                  color: isActive
                      ? accent.withValues(alpha: 0.28)
                      : cs.outlineVariant.withValues(alpha: 0.14),
                  width: 0.45,
                ),
                onTap: () => _handleBrandTap(context, themeProvider, brand),
                child: Row(
                  children: [
                    BrandBackgroundThumbnail(
                      key: ValueKey('theme_card_bg_${brand.id}'),
                      brand: brand,
                      fallback: Icon(
                        Icons.palette_outlined,
                        color: accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _styleName(brand),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _styleDescription(brand.style),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.66),
                                ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _swatch(brand.theme.colorScheme.primary),
                              _swatch(brand.theme.colorScheme.secondary),
                              _swatch(brand.theme.colorScheme.tertiary),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _applyIndicator(context, isActive, accent),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            AppSectionHeader(
              title: '专注背景',
              subtitle: I18n.tr('appearance.focus.subtitle'),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            ...themeProvider.focusBackdrops.map((backdrop) {
              final isActive =
                  themeProvider.activeFocusBackdrop.id == backdrop.id;
              final accent = backdrop.colors.first;
              return AppSurfaceCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                gradient: isActive
                    ? LinearGradient(
                        colors: [accent.withValues(alpha: 0.12), cs.surface],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                border: Border.all(
                  color: isActive
                      ? accent.withValues(alpha: 0.28)
                      : cs.outlineVariant.withValues(alpha: 0.14),
                  width: 0.45,
                ),
                onTap: () =>
                    _handleFocusBackdropTap(context, themeProvider, backdrop),
                child: Row(
                  children: [
                    _focusBackdropPreview(backdrop),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            backdrop.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            backdrop.description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.66),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _applyIndicator(context, isActive, accent),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            AppSectionHeader(
              title: '头像框',
              subtitle: I18n.tr('appearance.avatar.subtitle'),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            ...themeProvider.avatarFrames.map((frame) {
              final isActive = themeProvider.activeAvatarFrame.id == frame.id;
              final accent = frame.colors.first;
              return AppSurfaceCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                gradient: isActive
                    ? LinearGradient(
                        colors: [accent.withValues(alpha: 0.12), cs.surface],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                border: Border.all(
                  color: isActive
                      ? accent.withValues(alpha: 0.44)
                      : cs.outlineVariant.withValues(alpha: 0.35),
                ),
                onTap: () =>
                    _handleAvatarFrameTap(context, themeProvider, frame),
                child: Row(
                  children: [
                    _avatarFramePreview(frame, cs),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            frame.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            frame.description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.66),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _applyIndicator(context, isActive, accent),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            AppSectionHeader(
              title: '卡片皮肤',
              subtitle: I18n.tr('appearance.card.subtitle'),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            ...themeProvider.cardSkins.map((skin) {
              final isActive = themeProvider.activeCardSkin.id == skin.id;
              final accent = skin.colors.first;
              return AppSurfaceCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                gradient: isActive
                    ? LinearGradient(
                        colors: [accent.withValues(alpha: 0.18), cs.surface],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                border: Border.all(
                  color: isActive
                      ? accent.withValues(alpha: 0.5)
                      : cs.outlineVariant.withValues(alpha: 0.35),
                ),
                onTap: () => _handleCardSkinTap(context, themeProvider, skin),
                child: Row(
                  children: [
                    _cardSkinPreview(skin, cs),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            skin.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            skin.description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.66),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _applyIndicator(context, isActive, accent),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            const AppSectionHeader(
              title: '小组件主题',
              subtitle: '背景图和卡片皮肤会同步到手机桌面小组件',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            _widgetThemeSection(context, themeProvider),
          ],
        ),
      ),
    );
  }
}
