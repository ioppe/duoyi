import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final loggedIn in [false, true]) {
    testWidgets(
      'appearance applies freely offline for ${loggedIn ? 'zero balance account' : 'guest'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final theme = ThemeProvider();
        final achievements = AchievementProvider();
        await achievements.applyRewardsSnapshot({
          'balance': 0,
          'lifetime': 50,
          'ledger': [
            {'id': 'old', 'coins': 50},
          ],
        });
        var requests = 0;
        final auth = AuthProvider(
          initialState: loggedIn
              ? const AuthState(userId: 'user', token: 'token', coinBalance: 0)
              : const AuthState(),
          client: ApiClient(
            baseUrl: 'https://offline.test',
            httpClient: MockClient((_) async {
              requests++;
              return http.Response('server unavailable', 503);
            }),
          ),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<AchievementProvider>.value(
                value: achievements,
              ),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ],
            child: const MaterialApp(home: ThemePickerScreen()),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [
          I18n.tr('theme.style.liquid_glass.name'),
          '林间深呼吸',
          '金色勋章框',
          '纸感计划卡',
        ]) {
          await tester.scrollUntilVisible(
            find.text(label),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text(label).first);
          await tester.pumpAndSettle();
        }
        expect(theme.brand.id, 'liquidGlass');
        expect(theme.activeFocusBackdrop.id, 'forest_focus');
        expect(theme.activeAvatarFrame.id, 'golden_frame');
        expect(theme.activeCardSkin.id, 'paper_card');
        await tester.scrollUntilVisible(
          find.text('桌面小组件主题'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final brandChoice = find.widgetWithText(
          ChoiceChip,
          I18n.tr('theme.style.genshin.name'),
        );
        await tester.ensureVisible(brandChoice);
        await tester.tap(brandChoice);
        await tester.pumpAndSettle();
        final skinChoice = find.widgetWithText(ChoiceChip, '星光玻璃卡');
        await tester.ensureVisible(skinChoice);
        await tester.tap(skinChoice);
        await tester.pumpAndSettle();
        expect(theme.activeWidgetBackgroundId, 'genshin');
        expect(theme.activeWidgetCardSkinId, 'starlight_card');
        expect(requests, 0);
        expect(achievements.coinBalance, 0);
        expect(achievements.lifetimeCoins, 50);
        expect(achievements.rewardLedger, hasLength(1));
        expect(find.byIcon(Icons.lock_outline), findsNothing);
        expect(find.textContaining('时光币'), findsNothing);
        expect(find.textContaining('兑换'), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(
          jsonDecode(prefs.getString('theme_shop_state')!)['activeBrand'],
          'liquidGlass',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        theme.dispose();
        achievements.dispose();
        auth.dispose();
      },
    );
  }
}
