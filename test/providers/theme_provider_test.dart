import 'dart:convert';

import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('server theme shop state updates provider and local cache', () async {
    final provider = ThemeProvider();

    await provider.applyShopStateFromServer({
      'activeBrand': 're0',
      'switchCount': 1,
      'unlockedBrandIds': ['defaultBrand', 're0'],
      'activeFocusBackdropId': 'forest_focus',
      'unlockedFocusBackdropIds': ['classic_focus', 'forest_focus'],
      'updatedAt': '2026-06-01T00:00:00Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('theme_shop_state')!)
            as Map<String, dynamic>;

    expect(provider.brand.id, 're0');
    expect(provider.activeFocusBackdrop.id, 'forest_focus');
    expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:00Z');
    expect(persisted['activeBrand'], 're0');
    expect(persisted['activeFocusBackdropId'], 'forest_focus');
    expect(persisted['updatedAt'], '2026-06-01T00:00:00Z');
  });

  test(
    'server confirmed theme state can override local future timestamp',
    () async {
      final provider = ThemeProvider();

      await provider.applyShopStateFromServer({
        'activeBrand': 're0',
        'unlockedBrandIds': ['defaultBrand', 're0'],
        'updatedAt': '2026-06-01T00:00:10Z',
      });
      await provider.applyShopStateFromServer({
        'activeBrand': 'genshin',
        'unlockedBrandIds': ['defaultBrand', 're0', 'genshin'],
        'updatedAt': '2026-06-01T00:00:09Z',
      }, trusted: true);

      expect(provider.brand.id, 'genshin');
      expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:09Z');
    },
  );

  test(
    'theme shop state accepts snake case fields from old payloads',
    () async {
      final provider = ThemeProvider();

      await provider.applyShopStateFromServer({
        'active_brand': 'starRail',
        'unlocked_brand_ids': ['defaultBrand', 'starRail'],
        'active_focus_backdrop_id': 'ocean_focus',
        'unlocked_focus_backdrop_ids': ['classic_focus', 'ocean_focus'],
        'active_avatar_frame_id': 'golden_frame',
        'unlocked_avatar_frame_ids': ['simple_frame', 'golden_frame'],
        'active_card_skin_id': 'mint_card',
        'unlocked_card_skin_ids': ['plain_card', 'mint_card'],
        'active_widget_background_id': 'starRail',
        'active_widget_card_skin_id': 'mint_card',
        'switch_count': 3,
        'updated_at': '2026-06-01T00:00:03Z',
      });

      expect(provider.brand.id, 'starRail');
      expect(provider.activeFocusBackdrop.id, 'ocean_focus');
      expect(provider.activeAvatarFrame.id, 'golden_frame');
      expect(provider.activeCardSkin.id, 'mint_card');
      expect(provider.activeWidgetBackgroundId, 'starRail');
      expect(provider.activeWidgetCardSkin.id, 'mint_card');
      expect(provider.themeSwitchCount, 3);
    },
  );

  test(
    'widget theme overrides accept every legal resource and persist',
    () async {
      final provider = ThemeProvider();

      expect(await provider.setWidgetBackgroundBrand('re0'), isTrue);
      expect(await provider.setWidgetCardSkin('paper_card'), isTrue);
      expect(await provider.setWidgetBackgroundBrand('missing-brand'), isFalse);
      expect(await provider.setWidgetCardSkin('missing-skin'), isFalse);

      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('theme_shop_state')!)
              as Map<String, dynamic>;

      expect(provider.activeWidgetBackgroundBrand.id, 're0');
      expect(provider.activeWidgetCardSkin.id, 'paper_card');
      expect(persisted['activeWidgetBackgroundId'], 're0');
      expect(persisted['activeWidgetCardSkinId'], 'paper_card');
    },
  );

  test(
    'local theme shop changes include updatedAt for sync ordering',
    () async {
      final provider = ThemeProvider();

      await provider.loadFromStorage();
      await provider.unlockBrand('re0');
      await provider.setBrand('re0');
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('theme_shop_state')!)
              as Map<String, dynamic>;

      expect(provider.brand.id, 're0');
      expect(provider.shopStateUpdatedAt, isNotEmpty);
      expect(persisted['activeBrand'], 're0');
      expect(persisted['updatedAt'], isNotEmpty);
    },
  );

  test('older server theme shop state cannot roll back active theme', () async {
    final provider = ThemeProvider();

    await provider.applyShopStateFromServer({
      'activeBrand': 're0',
      'unlockedBrandIds': ['defaultBrand', 're0'],
      'updatedAt': '2026-06-01T00:00:02Z',
    });
    await provider.applyShopStateFromServer({
      'activeBrand': 'defaultBrand',
      'unlockedBrandIds': ['defaultBrand'],
      'updatedAt': '2026-06-01T00:00:01Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('theme_shop_state')!)
            as Map<String, dynamic>;

    expect(provider.brand.id, 're0');
    expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:02Z');
    expect(persisted['activeBrand'], 're0');
  });

  test(
    'older stored theme shop state cannot roll back in-memory theme',
    () async {
      final provider = ThemeProvider();

      await provider.applyShopStateFromServer({
        'activeBrand': 're0',
        'unlockedBrandIds': ['defaultBrand', 're0'],
        'updatedAt': '2026-06-01T00:00:02Z',
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'theme_shop_state',
        json.encode({
          'activeBrand': 'defaultBrand',
          'unlockedBrandIds': ['defaultBrand'],
          'updatedAt': '2026-06-01T00:00:01Z',
        }),
      );
      await provider.loadFromStorage();

      expect(provider.brand.id, 're0');
      expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:02Z');
    },
  );

  test('older server reward snapshot cannot roll back coin balance', () async {
    final provider = AchievementProvider();

    await provider.applyRewardsSnapshot({
      'balance': 60,
      'lifetime': 200,
      'updatedAt': '2026-06-01T00:00:02Z',
    });
    await provider.applyRewardsSnapshot({
      'balance': 120,
      'lifetime': 200,
      'updatedAt': '2026-06-01T00:00:01Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('duoyi_virtual_rewards')!)
            as Map<String, dynamic>;

    expect(provider.coinBalance, 60);
    expect(provider.lifetimeCoins, 200);
    expect(persisted['balance'], 60);
  });

  test(
    'loadFromStorage resets theme state when account keys are removed',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_brand': 're0',
        'theme_switch_count': 4,
        'theme_unlocked_brands': <String>['defaultBrand', 're0'],
        'theme_shop_state': json.encode({
          'activeBrand': 're0',
          'switchCount': 4,
          'unlockedBrandIds': ['defaultBrand', 're0'],
          'activeFocusBackdropId': 'forest_focus',
          'unlockedFocusBackdropIds': ['classic_focus', 'forest_focus'],
          'updatedAt': '2026-06-01T00:00:00.000Z',
        }),
      });
      final provider = ThemeProvider();

      await provider.loadFromStorage();
      expect(provider.brand.id, 're0');
      expect(provider.themeSwitchCount, 4);
      expect(provider.activeFocusBackdrop.id, 'forest_focus');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('theme_shop_state');
      await prefs.remove('active_brand');
      await prefs.remove('theme_switch_count');
      await prefs.remove('theme_unlocked_brands');
      await provider.loadFromStorage();

      expect(provider.brand.id, 'defaultBrand');
      expect(provider.themeSwitchCount, 0);
      expect(
        provider.unlockedBrandIds,
        provider.brands.map((item) => item.id).toSet(),
      );
      expect(
        provider.activeFocusBackdrop.id,
        ThemeProvider.defaultFocusBackdropId,
      );
      expect(
        provider.activeWidgetBackgroundId,
        ThemeProvider.widgetFollowThemeId,
      );
    },
  );
  test(
    'all resources are free with empty storage and legacy restricted state',
    () async {
      final provider = ThemeProvider();
      expect(provider.brands, hasLength(9));
      expect(provider.focusBackdrops, hasLength(5));
      expect(provider.avatarFrames, hasLength(4));
      expect(provider.cardSkins, hasLength(4));
      await provider.applyShopStateFromServer({
        'activeBrand': 'liquidGlass',
        'unlockedBrandIds': ['defaultBrand'],
      });
      expect(provider.brand.id, 'liquidGlass');
      for (final brand in provider.brands) {
        expect(provider.isBrandUnlocked(brand.id), isTrue);
        expect(await provider.setBrand(brand.id), isTrue);
        expect(await provider.setWidgetBackgroundBrand(brand.id), isTrue);
      }
      for (final item in provider.focusBackdrops) {
        expect(await provider.setFocusBackdrop(item.id), isTrue);
      }
      for (final item in provider.avatarFrames) {
        expect(await provider.setAvatarFrame(item.id), isTrue);
      }
      for (final item in provider.cardSkins) {
        expect(await provider.setCardSkin(item.id), isTrue);
        expect(await provider.setWidgetCardSkin(item.id), isTrue);
      }
      final beforeInvalid = provider.shopStateSnapshot;
      expect(await provider.setBrand('invalid'), isFalse);
      expect(await provider.setFocusBackdrop('invalid'), isFalse);
      expect(await provider.setAvatarFrame('invalid'), isFalse);
      expect(await provider.setCardSkin('invalid'), isFalse);
      expect(await provider.setWidgetBackgroundBrand('invalid'), isFalse);
      expect(await provider.setWidgetCardSkin('invalid'), isFalse);
      expect(provider.shopStateSnapshot, beforeInvalid);
      final restored = ThemeProvider();
      await restored.loadFromStorage();
      expect(restored.shopStateSnapshot, provider.shopStateSnapshot);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('duoyi_virtual_rewards'), isNull);
      provider.resetLocalState();
      expect(provider.unlockedBrandIds, hasLength(9));
      expect(await provider.setBrand('liquidGlass'), isTrue);
    },
  );
  test(
    'queued appearance changes preserve every selection and switch count',
    () async {
      final provider = ThemeProvider();
      expect(
        await Future.wait([
          provider.setBrand('re0'),
          provider.setFocusBackdrop('forest_focus'),
          provider.setAvatarFrame('golden_frame'),
          provider.setCardSkin('paper_card'),
          provider.setWidgetBackgroundBrand('genshin'),
          provider.setWidgetCardSkin('mint_card'),
          provider.setBrand('defaultBrand'),
        ]),
        everyElement(isTrue),
      );
      expect(provider.brand.id, 'defaultBrand');
      expect(provider.themeSwitchCount, 2);
      expect(provider.activeFocusBackdrop.id, 'forest_focus');
      expect(provider.activeAvatarFrame.id, 'golden_frame');
      expect(provider.activeCardSkin.id, 'paper_card');
      expect(provider.activeWidgetBackgroundId, 'genshin');
      expect(provider.activeWidgetCardSkinId, 'mint_card');
      final restored = ThemeProvider();
      await restored.loadFromStorage();
      expect(restored.shopStateSnapshot, provider.shopStateSnapshot);
    },
  );
}
