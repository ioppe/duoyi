import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/sync_status_presenter.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/sync_status_card.dart';

const _cardKey = ValueKey('sync_status_card');
const _spinnerKey = ValueKey('sync_status_card_spinner');
const _syncActionKey = ValueKey('sync_status_card_sync_action');

Widget _wrap(SyncStatusController? controller) {
  final child = const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: SyncStatusCard())),
  );
  if (controller == null) return child;
  return ChangeNotifierProvider<SyncStatusController>.value(
    value: controller,
    child: child,
  );
}

AppSurfaceCard _card(WidgetTester tester) =>
    tester.widget<AppSurfaceCard>(find.byKey(_cardKey));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 点击整卡并排空即时完成的微任务（回调立即返回时请求已收尾）。
  Future<void> tapCard(WidgetTester tester) async {
    await tester.tap(find.byKey(_cardKey));
    await tester.pump();
    await tester.pump();
  }

  test('SyncStatusController 转发底层 provider 的状态通知', () async {
    final cloud = CloudSyncProvider();
    var notifications = 0;
    final controller = SyncStatusController(source: cloud)
      ..addListener(() => notifications++);

    expect(controller.lastError, isNull);
    expect(controller.hasEverSynced, isFalse);
    // 未注入同步回调时不可手动触发。
    expect(controller.canSync, isFalse);

    // provider 状态变化（无 apiClientGetter → 置"请先登录"错误）应转发到 controller。
    await cloud.syncNow();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, greaterThan(0));
    expect(controller.lastError, '请先登录');

    controller.dispose();
    cloud.dispose();
  });

  test('single-flight：飞行中重复 requestSync 合流，回调只触发一次', () async {
    var calls = 0;
    final gate = Completer<void>();
    final controller = SyncStatusController(
      onSyncRequested: () {
        calls++;
        return gate.future;
      },
    );

    final first = controller.requestSync();
    final second = controller.requestSync();
    expect(identical(first, second), isTrue, reason: '进行中的请求应合流');
    expect(calls, 1);
    expect(controller.isSyncing, isTrue, reason: '同步中应覆盖整段回调耗时');
    expect(controller.canSync, isFalse);

    gate.complete();
    await first;
    expect(calls, 1);
    expect(controller.isSyncing, isFalse);
    expect(controller.syncRequestFailed, isFalse);
    expect(controller.canSync, isTrue);

    controller.dispose();
  });

  test('未注入回调时 requestSync 安全空操作', () async {
    final controller = SyncStatusController();
    expect(controller.canSync, isFalse);
    await controller.requestSync();
    expect(controller.isSyncing, isFalse);
    expect(controller.syncRequestFailed, isFalse);
    controller.dispose();
    // dispose 之后调用也不抛错。
    await controller.requestSync();
  });

  test('detach 后迟到的回调完成不通知、也不标记失败', () async {
    final gate = Completer<void>();
    var notifications = 0;
    final controller = SyncStatusController(onSyncRequested: () => gate.future);
    controller.addListener(() => notifications++);

    final pending = controller.requestSync();
    expect(controller.isSyncing, isTrue);
    controller.detach();
    final afterDetach = notifications;

    gate.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(notifications, afterDetach, reason: '迟到的完成不得再 notify');
    expect(controller.syncRequestFailed, isFalse);

    controller.dispose();
  });

  test('dispose 后迟到的回调完成不抛错、不 notify', () async {
    final gate = Completer<void>();
    final controller = SyncStatusController(onSyncRequested: () => gate.future);
    final pending = controller.requestSync();
    controller.dispose();

    gate.complete();
    await pending;
    expect(controller.isSyncing, isFalse);
  });

  test('换绑 source：旧请求不占用忙闲，A 迟到失败不改写 B 的状态', () async {
    final cloudA = CloudSyncProvider();
    final cloudB = CloudSyncProvider();
    final gateA = Completer<void>();
    final gateB = Completer<void>();
    var calls = 0;
    final controller = SyncStatusController(
      source: cloudA,
      onSyncRequested: () {
        calls++;
        return calls == 1 ? gateA.future : gateB.future;
      },
    );

    final first = controller.requestSync();
    expect(controller.isSyncing, isTrue);
    expect(controller.canSync, isFalse);

    controller.attach(cloudB);
    expect(controller.isSyncing, isFalse, reason: '换绑后旧请求不再占用忙闲状态');
    expect(controller.canSync, isTrue, reason: '换绑后新 source 可立即发起请求');

    final second = controller.requestSync();
    expect(calls, 2);
    expect(controller.isSyncing, isTrue);

    // B 失败：失败标记属于 B。
    gateB.completeError(StateError('new account failed'));
    await second;
    expect(controller.isSyncing, isFalse);
    expect(controller.syncRequestFailed, isTrue);

    // A 迟到失败：不得清除 B 的失败标记，也不重新置忙。
    gateA.completeError(StateError('old account failed'));
    await first;
    expect(controller.syncRequestFailed, isTrue, reason: '旧请求失败不得改写新请求的失败状态');
    expect(controller.isSyncing, isFalse);
    expect(controller.canSync, isTrue);

    controller.dispose();
    cloudA.dispose();
    cloudB.dispose();
  });

  test('detach + attach：旧请求迟到完成不清新请求的忙闲状态', () async {
    final cloudA = CloudSyncProvider();
    final cloudB = CloudSyncProvider();
    final gateA = Completer<void>();
    final gateB = Completer<void>();
    var calls = 0;
    final controller = SyncStatusController(
      source: cloudA,
      onSyncRequested: () {
        calls++;
        return calls == 1 ? gateA.future : gateB.future;
      },
    );

    final first = controller.requestSync();
    controller.detach();
    expect(controller.isSyncing, isFalse, reason: '解绑后旧请求不再占用忙闲状态');
    expect(controller.canSync, isTrue);

    controller.attach(cloudB);
    final second = controller.requestSync();
    expect(calls, 2);
    expect(controller.isSyncing, isTrue);

    // A 迟到成功：不得清除 B 的忙闲/失败状态。
    gateA.complete();
    await first;
    expect(controller.isSyncing, isTrue, reason: '旧请求迟到完成不得清 B 的 busy');
    expect(controller.canSync, isFalse);
    expect(controller.syncRequestFailed, isFalse);

    gateB.complete();
    await second;
    expect(controller.isSyncing, isFalse);
    expect(controller.canSync, isTrue);
    expect(controller.syncRequestFailed, isFalse);

    controller.dispose();
    cloudA.dispose();
    cloudB.dispose();
  });

  test('底层 provider 正在同步时 requestSync 不重复触发回调', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'todos': '[]'});
    final requestStarted = Completer<void>();
    final release = Completer<http.Response>();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync' && !requestStarted.isCompleted) {
          requestStarted.complete();
        }
        return release.future;
      }),
    );
    final cloud = CloudSyncProvider();
    cloud.apiClientGetter = () => client;
    cloud.serverConfigGetter = () => <String, dynamic>{'backup_enabled': true};
    var calls = 0;
    final controller = SyncStatusController(
      source: cloud,
      onSyncRequested: () async {
        calls++;
      },
    );

    final syncFuture = cloud.syncNow();
    await requestStarted.future.timeout(const Duration(seconds: 5));
    expect(cloud.isSyncing, isTrue);
    expect(controller.canSync, isFalse);

    await controller.requestSync();
    expect(calls, 0, reason: '底层已同步中，不应重复触发应用层回调');
    expect(controller.isSyncing, isTrue);

    release.complete(
      http.Response(
        json.encode(<String, dynamic>{
          'server_updated_at': '2026-06-11T00:00:00.000Z',
          'server_version': 2,
          'todos': <dynamic>[],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      ),
    );
    await syncFuture.timeout(const Duration(seconds: 5));
    expect(cloud.isSyncing, isFalse);
    expect(controller.canSync, isTrue);

    controller.dispose();
    cloud.dispose();
  });

  testWidgets('controller 未注入时整卡兜底为空', (tester) async {
    await tester.pumpWidget(_wrap(null));
    await tester.pump();
    expect(find.byKey(_cardKey), findsNothing);
  });

  testWidgets('从未同步且无回调：渲染引导文案，整卡不可点、无刷新入口', (tester) async {
    final cloud = CloudSyncProvider();
    final controller = SyncStatusController(source: cloud);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(controller.hasEverSynced, isFalse);
    expect(find.text(I18n.tr('sync.status.title')), findsOneWidget);
    expect(find.text(I18n.tr('sync.state.never')), findsOneWidget);
    expect(find.text(I18n.tr('sync.state.never_hint')), findsOneWidget);
    // 无应用层回调：整卡不可点、无刷新图标、不出现独立按钮组件。
    expect(_card(tester).onTap, isNull);
    expect(find.byKey(_syncActionKey), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    await tester.tap(find.byKey(_cardKey));
    await tester.pump();
    expect(controller.isSyncing, isFalse);

    controller.dispose();
    cloud.dispose();
  });

  testWidgets('已同步：显示上次同步时间，无待同步角标', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_last_time': '2026-06-07T12:00:00.000Z',
    });
    final cloud = CloudSyncProvider();
    await cloud.loadFromStorage();
    final controller = SyncStatusController(source: cloud);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(controller.hasEverSynced, isTrue);
    expect(find.text(I18n.tr('sync.state.synced')), findsOneWidget);
    expect(
      find.textContaining(I18n.tr('sync.last_sync_prefix')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sync_status_card_pending_badge')),
      findsNothing,
    );

    controller.dispose();
    cloud.dispose();
  });

  testWidgets('有本地改动未同步：已同步态追加待同步角标', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_last_time': '2026-06-07T12:00:00.000Z',
      'sync_pending_local_changes': true,
    });
    final cloud = CloudSyncProvider();
    await cloud.loadFromStorage();
    final controller = SyncStatusController(source: cloud);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(controller.hasPendingChanges, isTrue);
    expect(find.text(I18n.tr('sync.state.synced')), findsOneWidget);
    expect(find.text(I18n.tr('sync.pending_badge')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sync_status_card_pending_badge')),
      findsOneWidget,
    );

    controller.dispose();
    cloud.dispose();
  });

  testWidgets('同步中：渲染转圈与正在同步文案', (tester) async {
    final cloud = CloudSyncProvider();
    // 注意：Completer 不能跨 tester.runAsync 的 zone 边界传递（监听者
    // 留在 fake-async zone 不会被唤醒），这里用轮询布尔标志等待请求到达。
    var mockHit = false;
    final release = Completer<http.Response>();
    late Future<void> syncFuture;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') mockHit = true;
        return release.future;
      }),
    );
    cloud.apiClientGetter = () => client;
    cloud.serverConfigGetter = () => <String, dynamic>{'backup_enabled': true};
    final controller = SyncStatusController(source: cloud);

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();
    // 卡片初始为"尚未同步"态。
    expect(find.text(I18n.tr('sync.state.never')), findsOneWidget);

    await tester.runAsync(() async {
      syncFuture = cloud.syncNow();
      for (var i = 0; i < 50 && !mockHit; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();

    expect(mockHit, isTrue, reason: '同步请求应已到达 mock 客户端并保持阻塞');
    expect(controller.isSyncing, isTrue);
    expect(find.text(I18n.tr('sync.state.syncing')), findsOneWidget);
    expect(find.byKey(_spinnerKey), findsOneWidget);
    // 同步中不可再次手动触发。
    expect(_card(tester).onTap, isNull);
    expect(find.byKey(_syncActionKey), findsNothing);

    // 释放挂起的 mock 请求并等待同步真正收尾：避免挂起请求与 real-zone
    // timeout/timer 泄漏到后续用例。
    await tester.runAsync(() async {
      release.complete(
        http.Response(
          json.encode(<String, dynamic>{
            'server_updated_at': '2026-06-11T00:00:00.000Z',
            'server_version': 2,
            'todos': <dynamic>[],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      );
      await syncFuture.timeout(const Duration(seconds: 5));
    });
    expect(cloud.isSyncing, isFalse);
    expect(controller.isSyncing, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    cloud.dispose();
  });

  testWidgets('失败：显示失败原因与自动重试提示，无独立按钮', (tester) async {
    final cloud = CloudSyncProvider();
    // 服务端关闭 backup_enabled → 同步失败态（提前返回，不触网）。
    cloud.apiClientGetter = () => ApiClient(token: 'test-token');
    cloud.serverConfigGetter = () => <String, dynamic>{'backup_enabled': false};
    await cloud.syncNow();
    expect(cloud.lastError, '管理员已关闭云端备份');

    final controller = SyncStatusController(source: cloud);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(find.text(I18n.tr('sync.state.failed')), findsOneWidget);
    expect(find.text('管理员已关闭云端备份'), findsOneWidget);
    expect(find.text(I18n.tr('sync.state.auto_retry_hint')), findsOneWidget);
    // 不再有独立的按钮/重试组件，重试入口就是整卡（见下一个用例）。
    expect(find.byType(TextButton), findsNothing);
    expect(find.byKey(const ValueKey('sync_status_card_retry')), findsNothing);

    controller.dispose();
    cloud.dispose();
  });

  testWidgets('点击卡片经 controller 回调实际发出 mock /api/sync 请求', (tester) async {
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{}',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final controller = SyncStatusController(
      onSyncRequested: () =>
          client.post('/api/sync', <String, dynamic>{'todos': <dynamic>[]}),
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();
    expect(controller.canSync, isTrue);
    expect(find.byKey(_syncActionKey), findsOneWidget);
    expect(_card(tester).onTap, isNotNull);

    await tapCard(tester);

    expect(
      requests.map((request) => request.url.path),
      contains('/api/sync'),
      reason: '点击整卡应经 controller.requestSync() 真正发出同步请求',
    );

    controller.dispose();
  });

  testWidgets('连续点击 single-flight：同步中禁用点击，回调只触发一次', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    final controller = SyncStatusController(
      onSyncRequested: () {
        calls++;
        return gate.future;
      },
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();
    expect(find.byKey(_syncActionKey), findsOneWidget);

    await tester.tap(find.byKey(_cardKey));
    await tester.pump();
    expect(calls, 1);
    expect(controller.isSyncing, isTrue);
    expect(find.byKey(_spinnerKey), findsOneWidget);
    // 同步中：点击被禁用、刷新图标收起。
    expect(_card(tester).onTap, isNull);
    expect(find.byKey(_syncActionKey), findsNothing);

    await tester.tap(find.byKey(_cardKey), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1, reason: '同步中重复点击不得再次触发回调');

    // 直接重复调用同样合流（不并发触发第二次回调）。
    unawaited(controller.requestSync());
    expect(calls, 1);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(controller.isSyncing, isFalse);
    expect(controller.canSync, isTrue);
    expect(find.byKey(_syncActionKey), findsOneWidget);
    expect(find.byKey(_spinnerKey), findsNothing);

    controller.dispose();
  });

  testWidgets('已成功同步后仍可再次主动同步', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async {
        calls++;
      },
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    await tapCard(tester);
    expect(calls, 1);
    expect(controller.syncRequestFailed, isFalse);
    expect(controller.isSyncing, isFalse);
    expect(controller.canSync, isTrue);

    await tapCard(tester);
    expect(calls, 2, reason: '同步成功不代表入口关闭，用户可再次主动同步');

    controller.dispose();
  });

  testWidgets('回调失败：显示失败态且不泄露异常文本，可再次点击重试', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async {
        calls++;
        if (calls == 1) {
          throw StateError(
            'boom https://duoyi.test/api/sync?token=secret-token',
          );
        }
      },
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    await tapCard(tester);
    expect(calls, 1);
    expect(controller.syncRequestFailed, isTrue);
    expect(controller.isSyncing, isFalse);
    expect(find.text(I18n.tr('sync.state.failed')), findsOneWidget);
    // 异常文本（可能含地址 / token）不得出现在 UI 上。
    expect(find.textContaining('secret-token'), findsNothing);
    expect(find.textContaining('https://duoyi.test'), findsNothing);
    // 失败后仍可点击重试。
    expect(controller.canSync, isTrue);
    expect(_card(tester).onTap, isNotNull);

    await tapCard(tester);
    expect(calls, 2);
    expect(controller.syncRequestFailed, isFalse);
    expect(find.text(I18n.tr('sync.state.failed')), findsNothing);

    controller.dispose();
  });

  testWidgets('手动失败后底层真实同步成功即清除失败态', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'todos': '[]'});
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          return http.Response(
            json.encode(<String, dynamic>{
              'server_updated_at': '2026-06-11T00:00:00.000Z',
              'server_version': 2,
              'todos': <dynamic>[],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      }),
    );
    final cloud = CloudSyncProvider();
    cloud.apiClientGetter = () => client;
    cloud.serverConfigGetter = () => <String, dynamic>{'backup_enabled': true};
    var calls = 0;
    final controller = SyncStatusController(
      source: cloud,
      onSyncRequested: () async {
        calls++;
        // 模拟应用层刷新公共后端配置阶段失败。
        throw StateError('config refresh failed');
      },
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    await tapCard(tester);
    expect(calls, 1);
    expect(controller.syncRequestFailed, isTrue);
    expect(find.text(I18n.tr('sync.state.failed')), findsOneWidget);

    // 底层真实同步成功（mock /api/sync）：应清除旧的"手动失败"标记。
    await tester.runAsync(() async {
      await cloud.syncNow();
    });
    await tester.pump();

    expect(cloud.hasEverSynced, isTrue);
    expect(
      controller.syncRequestFailed,
      isFalse,
      reason: '底层确实更新的成功同步应清除旧的手动失败标记',
    );
    expect(find.text(I18n.tr('sync.state.failed')), findsNothing);
    expect(find.text(I18n.tr('sync.state.synced')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    cloud.dispose();
  });

  test('requestSync 经回调驱动真实 provider 发出 /api/sync 并完成', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'todos': '[]'});
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        requests.add(request.url.path);
        return http.Response(
          json.encode(<String, dynamic>{
            'server_updated_at': '2026-06-11T00:00:00.000Z',
            'server_version': 2,
            'todos': <dynamic>[],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final cloud = CloudSyncProvider();
    cloud.apiClientGetter = () => client;
    cloud.serverConfigGetter = () => <String, dynamic>{'backup_enabled': true};
    // 应用层回调的真实形态：先刷新配置、再同步业务数据（此处即 syncNow）。
    final controller = SyncStatusController(
      source: cloud,
      onSyncRequested: cloud.syncNow,
    );

    await controller.requestSync();

    expect(requests, contains('/api/sync'));
    expect(controller.isSyncing, isFalse);
    expect(controller.syncRequestFailed, isFalse);
    expect(controller.hasEverSynced, isTrue);

    controller.dispose();
    cloud.dispose();
  });

  test('sync.* 词条 zh/en 双语存在且不回退', () {
    addTearDown(() => I18n.setLocale(AppLocale.zh));
    const keys = <String>[
      'sync.status.title',
      'sync.state.never',
      'sync.state.never_hint',
      'sync.state.syncing',
      'sync.state.synced',
      'sync.state.failed',
      'sync.state.auto_retry_hint',
      'sync.last_sync_prefix',
      'sync.pending_badge',
      'sync.action.sync_now',
    ];
    I18n.setLocale(AppLocale.zh);
    for (final key in keys) {
      expect(I18n.tr(key), isNot(key), reason: '$key 缺少 zh 词条');
    }
    // en 缺失时 tr 会静默回退 zh，因此对 en 断言具体英文值。
    I18n.setLocale(AppLocale.en);
    const expectedEn = <String, String>{
      'sync.status.title': 'Cloud sync',
      'sync.state.never': 'Not synced yet',
      'sync.state.never_hint':
          'Sign in and enable cloud sync to back up your data automatically',
      'sync.state.syncing': 'Syncing…',
      'sync.state.synced': 'Synced',
      'sync.state.failed': 'Sync failed',
      'sync.state.auto_retry_hint':
          'Will retry automatically in the background',
      'sync.last_sync_prefix': 'Last synced ',
      'sync.pending_badge': 'Pending',
      'sync.action.sync_now': 'Sync now',
    };
    for (final key in keys) {
      expect(I18n.tr(key), expectedEn[key], reason: '$key 的 en 词条不符');
    }
  });
}
