import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('全部外观免费应用且保留同步备份兼容', () {
    final themeProvider = File(
      'lib/providers/theme_provider.dart',
    ).readAsStringSync();
    final themeScreen = File(
      'lib/screens/theme_picker_screen.dart',
    ).readAsStringSync();
    final achievementProvider = File(
      'lib/providers/achievement_provider.dart',
    ).readAsStringSync();
    final backup = File('lib/services/backup_service.dart').readAsStringSync();
    final cloudSync = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(themeProvider, contains('premiumBrandCost'));
    expect(themeProvider, contains('theme_unlocked_brands'));
    expect(themeProvider, contains('theme_shop_state'));
    expect(themeProvider, contains('updatedAt'));
    expect(themeProvider, contains('applyShopStateFromServer'));
    expect(themeProvider, contains('shopStateSnapshot'));
    expect(themeProvider, contains('isBrandUnlocked'));
    expect(themeProvider, contains('unlockBrand'));
    expect(themeProvider, contains('brandCost'));
    expect(themeProvider, contains('FocusBackdropReward'));
    expect(themeProvider, contains('focusBackdropRewards'));
    expect(themeProvider, contains('isFocusBackdropUnlocked'));
    expect(themeProvider, contains('unlockFocusBackdrop'));
    expect(themeProvider, contains('setFocusBackdrop'));
    expect(themeProvider, contains('activeFocusBackdropId'));
    expect(themeProvider, contains('unlockedFocusBackdropIds'));
    expect(themeProvider, contains('AvatarFrameReward'));
    expect(themeProvider, contains('avatarFrameRewards'));
    expect(themeProvider, contains('isAvatarFrameUnlocked'));
    expect(themeProvider, contains('unlockAvatarFrame'));
    expect(themeProvider, contains('setAvatarFrame'));
    expect(themeProvider, contains('activeAvatarFrameId'));
    expect(themeProvider, contains('unlockedAvatarFrameIds'));
    expect(themeProvider, contains('CardSkinReward'));
    expect(themeProvider, contains('cardSkinRewards'));
    expect(themeProvider, contains('isCardSkinUnlocked'));
    expect(themeProvider, contains('unlockCardSkin'));
    expect(themeProvider, contains('setCardSkin'));
    expect(themeProvider, contains('activeCardSkinId'));
    expect(themeProvider, contains('unlockedCardSkinIds'));
    expect(themeProvider, contains('activeWidgetBackgroundId'));
    expect(themeProvider, contains('activeWidgetCardSkinId'));
    expect(themeProvider, contains('setWidgetBackgroundBrand'));
    expect(themeProvider, contains('setWidgetCardSkin'));
    for (final hidden in [
      '时光币',
      'spendCoins',
      'coinBalance',
      '.cost',
      'brandCost(',
      'Icons.lock_outline',
      '兑换',
      '购买',
      'isBrandUnlocked(',
      'isCardSkinUnlocked(',
    ]) {
      expect(themeScreen, isNot(contains(hidden)), reason: hidden);
    }
    expect(themeScreen, contains("I18n.tr('appearance.title')"));
    expect(themeScreen, contains("I18n.tr('appearance.free')"));
    expect(themeScreen, contains('await applyLocal()'));
    expect(themeScreen, contains('!ok'));
    expect(themeScreen, isNot(contains('.applyThemeShopItem(')));
    expect(themeScreen, contains('guestAppearanceMarkerKey'));
    expect(themeScreen, contains('isCurrentAccountDataGeneration'));
    expect(themeScreen, contains('专注背景'));
    expect(themeScreen, contains('_focusBackdropPreview'));
    expect(themeScreen, contains('头像框'));
    expect(themeScreen, contains('_avatarFramePreview'));
    expect(themeScreen, contains('卡片皮肤'));
    expect(themeScreen, contains('_cardSkinPreview'));
    expect(themeScreen, contains('小组件主题'));
    expect(themeScreen, contains('_widgetThemeSection'));
    expect(themeScreen, contains('provider.setWidgetBackgroundBrand'));
    expect(themeScreen, contains('provider.setWidgetCardSkin'));
    expect(achievementProvider, contains('Future<bool> spendCoins'));
    expect(achievementProvider, contains('Future<void> applyRewardsSnapshot'));
    expect(backup, contains("'theme_shop_state'"));
    expect(cloudSync, contains("'theme_shop_state': 'theme_shop_state'"));
  });

  test('番茄钟页面展示已启用的专注背景装饰', () {
    final pomodoroScreen = File(
      'lib/screens/pomodoro_screen.dart',
    ).readAsStringSync();

    expect(pomodoroScreen, contains('activeFocusBackdrop'));
    expect(pomodoroScreen, contains('defaultFocusBackdropId'));
    expect(pomodoroScreen, contains('focusBackdrop.colors'));
    expect(pomodoroScreen, contains('focusBackdrop.name'));
  });

  test('我的页面展示已启用的头像框装饰', () {
    final mineScreen = File('lib/screens/mine_screen.dart').readAsStringSync();

    expect(mineScreen, contains('activeAvatarFrame'));
    expect(mineScreen, contains('defaultAvatarFrameId'));
    expect(mineScreen, contains('avatarFrame.colors'));
  });

  test('全局信息卡片应用已启用的卡片皮肤', () {
    final surface = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    expect(surface, contains('activeCardSkin'));
    expect(surface, contains('defaultCardSkinId'));
    expect(surface, contains('skinGradient'));
    expect(surface, contains('cardSkin.colors'));
  });
}
