import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/feature_flags.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/sync_status_presenter.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/backend_sync_coordinator.dart';
import 'package:duoyi/widgets/app_pull_to_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _hash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json'},
);

class _HabitSyncFixture {
  final requests = <String>[];
  final habits = HabitProvider();
  final cloud = CloudSyncProvider();
  late final AuthProvider auth;
  late final BackendSyncCoordinator coordinator;
  late final SyncStatusController controller;
  late final Habit seed;
  List<Map<String, dynamic>> remoteHabits = [];
  Map<String, dynamic> serverCollections = {};
  Future<void> Function()? beforeLocalLoad;
  bool configFails = false;
  int changedCallbacks = 0;
  int localLoads = 0;
  bool _disposed = false;

  List<String> get syncRequests =>
      requests.where((path) => path.startsWith('POST /api/sync')).toList();

  Future<void> loadLocal() async {
    localLoads++;
    await beforeLocalLoad?.call();
    await habits.loadFromStorage();
  }

  static Future<_HabitSyncFixture> create({bool autoSync = true}) async {
    final fixture = _HabitSyncFixture();
    final now = DateTime.now().toUtc();
    fixture.seed = Habit(
      id: 'cached-habit',
      name: '缓存阅读习惯',
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now.subtract(const Duration(minutes: 10)),
    );
    fixture.remoteHabits = [fixture.seed.toJson()];
    SharedPreferences.setMockInitialValues({
      'sync_auto': autoSync,
      'habits': jsonEncode(fixture.remoteHabits),
    });
    final client = ApiClient(
      baseUrl: 'https://habit-sync.test',
      token: 'fixture-token',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        fixture.requests.add('${request.method} $path');
        if (path == '/api/config') {
          return fixture.configFails
              ? _json({'detail': 'fixture offline'}, 503)
              : _json({'backup_enabled': true, 'ai_enabled': false});
        }
        if (request.method == 'POST' && path.startsWith('/api/sync')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (path == '/api/sync') {
            fixture.serverCollections = Map<String, dynamic>.from(body);
          } else if (path == '/api/sync/delta') {
            fixture.serverCollections.addAll(
              Map<String, dynamic>.from(body['collections'] as Map),
            );
          }
          fixture.serverCollections['habits'] = fixture.remoteHabits;
          return _json({
            'server_version': fixture.syncRequests.length,
            'server_updated_at': '2026-11-11T08:00:00.000Z',
            'habits': fixture.remoteHabits,
            'collection_hashes': {
              for (final entry in fixture.serverCollections.entries)
                entry.key: _hash(entry.value),
            },
          });
        }
        return _json({});
      }),
    );
    fixture.auth = AuthProvider(
      initialState: const AuthState(
        userId: 'habit-fixture-user',
        username: 'habit-fixture',
        token: 'fixture-token',
      ),
      client: client,
    );
    fixture.cloud.apiClientGetter = () => fixture.auth.client;
    fixture.cloud.serverConfigGetter = () => fixture.auth.serverConfig;
    fixture.cloud.onSynced = (collections) async {
      fixture.changedCallbacks++;
      if (collections.contains('habits')) {
        await fixture.habits.loadFromStorage();
      }
    };
    await fixture.cloud.loadFromStorage();
    fixture.coordinator = BackendSyncCoordinator(
      auth: fixture.auth,
      cloud: fixture.cloud,
      ensureLocalDataLoaded: fixture.loadLocal,
    );
    fixture.controller = SyncStatusController(
      source: fixture.cloud,
      onSyncRequested: () => fixture.coordinator.refresh(force: true),
    );
    addTearDown(fixture.dispose);
    return fixture;
  }

  Future<void> establishUnchangedBaseline() async {
    await cloud.syncNow();
    expect(cloud.lastError, isNull);
    expect(changedCallbacks, 0);
    expect(habits.habits, isEmpty);
    requests.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    coordinator.dispose();
    cloud.dispose();
    habits.dispose();
    auth.dispose();
  }
}

Future<void> _pumpHabitPage(
  WidgetTester tester,
  _HabitSyncFixture fixture,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HabitProvider>.value(value: fixture.habits),
        ChangeNotifierProvider<SyncStatusController>.value(
          value: fixture.controller,
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MaterialApp(home: AppPullToSync(child: HabitScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pullHabitPage(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('habit_today_scroll_view')),
    const Offset(0, 350),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FeatureFlags.resetAllOverrides();
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(FeatureFlags.resetAllOverrides);

  test('启动同步在零远端变化回调时也水合已有习惯', () async {
    final fixture = await _HabitSyncFixture.create();
    await fixture.establishUnchangedBaseline();
    await fixture.coordinator.refresh();

    expect(fixture.requests.take(2), [
      'GET /api/config',
      'POST /api/sync/pull',
    ]);
    expect(fixture.syncRequests, ['POST /api/sync/pull']);
    expect(fixture.changedCallbacks, 0);
    expect(fixture.localLoads, 1);
    expect(fixture.habits.habits.single.name, fixture.seed.name);
  });

  test('启动时无本地编辑仍立即拉取已有习惯的新打卡记录', () async {
    final fixture = await _HabitSyncFixture.create();
    await fixture.establishUnchangedBaseline();
    final day = AppClock.today();
    final key = day.toIso8601String().split('T').first;
    final remote = Habit.fromJson(fixture.seed.toJson())
      ..name = '远端更新习惯'
      ..updatedAt = DateTime.now().toUtc().add(const Duration(seconds: 1));
    remote.completions[key] = 1;
    remote.completionUpdatedAt[key] = remote.updatedAt;
    fixture.remoteHabits = [remote.toJson()];

    await fixture.coordinator.refresh();

    expect(fixture.syncRequests, ['POST /api/sync/pull']);
    expect(fixture.habits.habits, hasLength(1));
    expect(fixture.habits.habits.single.name, remote.name);
    expect(fixture.habits.habits.single.countForDate(day), 1);
  });

  test('断网配置失败时独立本地水合仍可读出缓存习惯', () async {
    final fixture = await _HabitSyncFixture.create(autoSync: false);
    fixture.configFails = true;
    await fixture.loadLocal();
    await expectLater(
      fixture.coordinator.refresh(force: true),
      throwsA(isA<BackendSyncConfigException>()),
    );
    expect(fixture.syncRequests, isEmpty);
    expect(fixture.habits.habits.single.name, fixture.seed.name);
  });

  test('业务水合失败不会冒充刷新成功，后续手动刷新可重试', () async {
    final fixture = await _HabitSyncFixture.create(autoSync: false);
    fixture.beforeLocalLoad = () async =>
        throw StateError('fixture load failed');
    await fixture.controller.requestSync();
    expect(fixture.controller.syncRequestFailed, isTrue);
    expect(fixture.habits.habits, isEmpty);
    fixture.beforeLocalLoad = null;
    await fixture.controller.requestSync();
    expect(fixture.controller.syncRequestFailed, isFalse);
    expect(fixture.habits.habits.single.name, fixture.seed.name);
  });

  test('初始业务水合期间到来的手动刷新仍拉取点击后的习惯快照', () async {
    final fixture = await _HabitSyncFixture.create();
    await fixture.establishUnchangedBaseline();
    final loadStarted = Completer<void>();
    final releaseLoad = Completer<void>();
    fixture.beforeLocalLoad = () {
      if (!loadStarted.isCompleted) loadStarted.complete();
      return releaseLoad.future;
    };
    final background = fixture.coordinator.refresh();
    await loadStarted.future.timeout(const Duration(seconds: 2));
    final day = AppClock.today();
    final key = day.toIso8601String().split('T').first;
    final remote = Habit.fromJson(fixture.seed.toJson())
      ..name = '水合期间新更新的习惯'
      ..updatedAt = DateTime.now().toUtc().add(const Duration(seconds: 1));
    remote.completions[key] = 1;
    remote.completionUpdatedAt[key] = remote.updatedAt;
    fixture.remoteHabits = [remote.toJson()];

    final manual = fixture.controller.requestSync();
    expect(fixture.controller.isSyncing, isTrue);
    releaseLoad.complete();
    await Future.wait([background, manual]);

    expect(fixture.syncRequests, [
      'POST /api/sync/pull',
      'POST /api/sync/pull',
    ]);
    expect(fixture.habits.habits.single.name, remote.name);
    expect(fixture.habits.habits.single.countForDate(day), 1);
    expect(fixture.controller.syncRequestFailed, isFalse);
  });

  testWidgets(
    '习惯页真实下拉等待缓存回载后才结束转圈并显示已有习惯',
    (tester) async {
      final fixture = await _HabitSyncFixture.create(autoSync: false);
      await fixture.establishUnchangedBaseline();
      final releaseLoad = Completer<void>();
      final loadStarted = Completer<void>();
      fixture.beforeLocalLoad = () {
        if (!loadStarted.isCompleted) loadStarted.complete();
        return releaseLoad.future;
      };
      await _pumpHabitPage(tester, fixture);
      expect(find.text(fixture.seed.name), findsNothing);

      await _pullHabitPage(tester);
      expect(loadStarted.isCompleted, isTrue);
      expect(fixture.controller.isSyncing, isTrue);
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      expect(find.text(fixture.seed.name), findsNothing);
      expect(fixture.changedCallbacks, 0);

      releaseLoad.complete();
      await tester.pumpAndSettle();
      expect(fixture.controller.isSyncing, isFalse);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(find.text(fixture.seed.name), findsOneWidget);
      expect(fixture.syncRequests, ['POST /api/sync/pull']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    '已有习惯数量不变时下拉立即刷新名称和打卡内容',
    (tester) async {
      final fixture = await _HabitSyncFixture.create(autoSync: false);
      await fixture.establishUnchangedBaseline();
      await fixture.loadLocal();
      await _pumpHabitPage(tester, fixture);
      expect(find.text(fixture.seed.name), findsOneWidget);
      final day = AppClock.today();
      final key = day.toIso8601String().split('T').first;
      final remote = Habit.fromJson(fixture.seed.toJson())
        ..name = '手动同步后的习惯'
        ..updatedAt = DateTime.now().toUtc().add(const Duration(seconds: 1));
      remote.completions[key] = 1;
      remote.completionUpdatedAt[key] = remote.updatedAt;
      fixture.remoteHabits = [remote.toJson()];

      await _pullHabitPage(tester);
      await tester.pumpAndSettle();
      expect(fixture.habits.habits, hasLength(1));
      expect(fixture.habits.habits.single.countForDate(day), 1);
      expect(find.text(remote.name), findsOneWidget);
      expect(find.text(fixture.seed.name), findsNothing);
      expect(fixture.controller.isSyncing, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
