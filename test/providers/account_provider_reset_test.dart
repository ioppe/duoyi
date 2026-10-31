import 'dart:convert';
import 'dart:io';

import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'AchievementProvider resetLocalState clears reward and unlock memory',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_achievements_unlocked': jsonEncode({
          'first_admin_achievement': '2026-06-01T00:00:00.000Z',
        }),
        'duoyi_achievements_notified': <String>['first_admin_achievement'],
        'duoyi_virtual_rewards': jsonEncode({
          'balance': 88,
          'lifetime': 120,
          'grantIds': <String>['admin-grant'],
          'ledger': <Map<String, Object>>[
            {
              'id': 'admin-grant',
              'title': 'Admin reward',
              'coins': 88,
              'reason': 'old account data',
              'awardedAt': '2026-06-01T00:00:00.000Z',
            },
          ],
          'updatedAt': '2026-06-01T00:00:00.000Z',
        }),
      });
      final provider = AchievementProvider();
      await provider.loadFromStorage();

      expect(provider.unlockedAt, isNotEmpty);
      expect(provider.coinBalance, 88);
      expect(provider.lifetimeCoins, 120);
      expect(provider.rewardLedger, hasLength(1));
      final revisionBeforeReset = provider.persistedRevision;

      provider.resetLocalState();

      expect(provider.unlockedAt, isEmpty);
      expect(provider.snapshots, isEmpty);
      expect(provider.coinBalance, 0);
      expect(provider.lifetimeCoins, 0);
      expect(provider.rewardLedger, isEmpty);
      expect(provider.lastEventAt, isNull);
      expect(provider.persistedRevision, revisionBeforeReset + 1);
      provider.dispose();
    },
  );

  test(
    'FocusRoomProvider resetLocalState clears joined rooms and social caches',
    () async {
      final provider = FocusRoomProvider();
      final customRoom = await provider.createRoom(
        name: 'Admin room',
        description: 'old account room',
        weeklyTargetMinutes: 30,
      );

      expect(provider.roomById(customRoom.id), isNotNull);
      expect(provider.joinedRoomIds, contains(customRoom.id));
      expect(provider.activeRoomId, customRoom.id);

      provider.resetLocalState();

      expect(provider.roomById(customRoom.id), isNull);
      expect(provider.joinedRoomIds, {FocusRoomProvider.defaultRoomId});
      expect(provider.activeRoomId, FocusRoomProvider.defaultRoomId);
      expect(provider.focusFriends, isEmpty);
      expect(provider.incomingFriendRequests, isEmpty);
      expect(provider.outgoingFriendRequests, isEmpty);
      expect(provider.lastRemoteError, isNull);
      expect(provider.fallbackToLocal, isFalse);
      provider.dispose();
    },
  );

  test('PomodoroProvider resetLocalState clears focus control memory', () {
    final source = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final start = source.indexOf('  void resetLocalState() {');
    final end = source.indexOf('  void _initState()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final resetBody = source.substring(start, end);

    expect(resetBody, contains('_timerTicks.value = 0;'));
    expect(
      resetBody,
      contains('_dndStatus = const FocusDndStatus.unavailable();'),
    );
    expect(resetBody, contains('_dndActive = false;'));
    expect(resetBody, contains('_dndEnableInFlight = false;'));
    expect(
      resetBody,
      contains(
        '_distractionStatus = const FocusDistractionStatus.unavailable();',
      ),
    );
    expect(resetBody, contains('_lastDistractingPackage = null;'));
    expect(
      resetBody,
      contains(
        '_distraction.setFocusBlocker(enabled: false, packages: const []);',
      ),
    );
  });

  test(
    'AuthProvider clears auth and account prefs when logout cleanup fails',
    () async {
      const adminState = AuthState(
        userId: 'admin-id',
        username: 'admin',
        token: 'admin-token',
        coinBalance: 999,
        lifetimeCoins: 1999,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_state': jsonEncode(adminState.toJson()),
        'habits': '[{"name":"admin habit"}]',
        'active_brand': 'admin-theme',
        'duoyi_virtual_rewards': jsonEncode(<String, Object>{
          'balance': 999,
          'lifetime': 1999,
        }),
      });

      final auth = AuthProvider(
        initialState: adminState,
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/logout');
            return http.Response(
              jsonEncode(<String, Object>{'ok': true}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountLoggedOut = () async {
        throw StateError('cleanup failed');
      };

      await expectLater(auth.logout(), throwsStateError);

      final prefs = await SharedPreferences.getInstance();
      expect(auth.state.isLoggedIn, isFalse);
      expect(auth.state.userId, isNull);
      expect(auth.state.coinBalance, 0);
      expect(auth.client.token, isNull);
      expect(prefs.getString('auth_state'), isNull);
      expect(prefs.getString('habits'), isNull);
      // 主题视图是设备选择，清理账号数据后仍保留。
      expect(prefs.getString('active_brand'), 'admin-theme');
      expect(prefs.getString('duoyi_virtual_rewards'), isNull);
    },
  );

  test(
    'AuthProvider keeps previous account when switch cleanup fails',
    () async {
      const adminState = AuthState(
        userId: 'admin-id',
        username: 'admin',
        token: 'admin-token',
        coinBalance: 999,
        lifetimeCoins: 1999,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_state': jsonEncode(adminState.toJson()),
        'habits': '[{"name":"admin habit"}]',
        'active_brand': 'admin-theme',
        'duoyi_virtual_rewards': jsonEncode(<String, Object>{
          'balance': 999,
          'lifetime': 1999,
        }),
      });

      final auth = AuthProvider(
        initialState: adminState,
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/login');
            return http.Response(
              jsonEncode(<String, Object>{
                'user_id': 'test-id',
                'username': 'test',
                'token': 'test-token',
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountIdentityChanging = (previous, next) async {
        expect(previous.userId, 'admin-id');
        expect(next.userId, 'test-id');
        expect(auth.state.userId, 'admin-id');
        throw StateError('cleanup failed');
      };

      await expectLater(
        auth.login(username: 'test', password: 'pw'),
        throwsStateError,
      );

      final prefs = await SharedPreferences.getInstance();
      final persisted =
          jsonDecode(prefs.getString('auth_state')!) as Map<String, dynamic>;
      expect(auth.state.userId, 'admin-id');
      expect(auth.state.coinBalance, 999);
      expect(auth.client.token, 'admin-token');
      expect(persisted['user_id'], 'admin-id');
      expect(persisted['coin_balance'], 999);
      expect(prefs.getString('habits'), isNotNull);
      expect(prefs.getString('active_brand'), 'admin-theme');
      expect(prefs.getString('duoyi_virtual_rewards'), isNotNull);
    },
  );
}
