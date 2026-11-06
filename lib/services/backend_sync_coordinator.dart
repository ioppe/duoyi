import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/i18n.dart';
import '../models/server_config_status.dart';
import '../providers/auth_provider.dart';
import '../providers/cloud_sync_provider.dart';
import 'api_client.dart';

/// `/api/config` 没拿到时抛出的**无秘密**异常。
///
/// 只带一条 I18n 兜底文案，绝不含服务器地址、token 或响应体，可以直接用于
/// 界面提示或日志。
class BackendSyncConfigException implements Exception {
  const BackendSyncConfigException();

  /// 面向用户的文案（`sync.config.failed`）。
  String get message => I18n.tr('sync.config.failed');

  @override
  String toString() => 'BackendSyncConfigException';
}

/// 把「刷新服务器配置 → 校验当前身份 → 按需同步个人数据」收敛成一个可测试服务。
///
/// 约束（与 `docs/cloud-sync-v2-contract.md` 的既有语义一致，不新增协议）：
/// - **配置先行**：任何同步动作之前先拉公开的 `/api/config`；guest 只做这一步。
/// - **不冒充成功**：配置 `failed` 时抛 [BackendSyncConfigException]，不会出现
///   「同步成功」；管理员 `backup_enabled=false` 只停轮询，错误由
///   [CloudSyncProvider.syncNow] 用既有文案产出，绝不强开。
/// - **尊重用户开关**：`autoSync=false` 时后台调用不同步；用户手动的
///   `force: true` 只额外执行一次，不擅自开启轮询。
/// - **换号/换服务器安全**：所有 await 之后都重新校验 ApiClient 身份与代际，
///   旧连接或 [dispose] 之后的任务不会 resume、轮询或写状态。
/// - 增量合并、本地优先、账号代际仍完全由 [CloudSyncProvider] 负责。
class BackendSyncCoordinator {
  BackendSyncCoordinator({
    required AuthProvider auth,
    required CloudSyncProvider cloud,
  }) : _auth = auth,
       _cloud = cloud;

  final AuthProvider _auth;
  final CloudSyncProvider _cloud;

  Future<void>? _inFlight;
  ApiClient? _inFlightClient;
  bool _forceRequested = false;
  int _generation = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// 刷新配置并在已登录时同步一次；`force` 绕过配置 TTL 与 autoSync 后台限制，
  /// 但不会绕过在途 singleflight。
  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future.value();
    final inFlight = _inFlight;
    if (inFlight != null && identical(_inFlightClient, _auth.client)) {
      // 用户操作可升级正在加载配置的后台请求，不再发第二个配置请求。
      if (force) _forceRequested = true;
      return inFlight;
    }
    final completer = Completer<void>();
    final generation = _generation;
    final startClient = _auth.client;
    _inFlight = completer.future;
    _inFlightClient = startClient;
    _forceRequested = force;
    unawaited(
      _runRefresh(
        completer,
        generation: generation,
        startClient: startClient,
        force: force,
      ),
    );
    return completer.future;
  }

  Future<void> _runRefresh(
    Completer<void> completer, {
    required int generation,
    required ApiClient startClient,
    required bool force,
  }) async {
    Object? error;
    StackTrace? stackTrace;
    try {
      await _refreshAndSync(
        generation: generation,
        startClient: startClient,
        force: force,
      );
    } catch (e, st) {
      error = e;
      stackTrace = st;
    } finally {
      if (identical(_inFlight, completer.future)) {
        _inFlight = null;
        _inFlightClient = null;
        _forceRequested = false;
      }
      if (!completer.isCompleted) {
        if (error != null) {
          completer.completeError(error, stackTrace);
        } else {
          completer.complete();
        }
      }
    }
  }

  /// 身份是否仍是发起时的那个连接（换号、换服务器、退出、dispose 后都为 false）。
  bool _isCurrent(int generation, ApiClient startClient) =>
      !_disposed &&
      generation == _generation &&
      identical(startClient, _auth.client);

  Future<void> _refreshAndSync({
    required int generation,
    required ApiClient startClient,
    required bool force,
  }) async {
    // 1) 配置先行：/api/config 是公开接口，guest 也必须走这一步。
    await _auth.refreshServerConfigFromServer(force: force);
    if (!_isCurrent(generation, startClient)) return;
    if (_auth.serverConfigStatus == ServerConfigStatus.failed) {
      // 不能把「没拿到配置」当成同步成功，也不能开始轮询。
      _cloud.stopRemotePolling();
      throw const BackendSyncConfigException();
    }

    // 2) guest：只读公开配置，绝不请求任何个人数据接口。
    if (!_auth.state.isLoggedIn) return;
    if (!identical(startClient, _auth.client)) return;

    // 后台刷新尊重自动同步开关；在途刷新收到的手动请求也执行这一次。
    if (!_cloud.config.autoSync && !(force || _forceRequested)) {
      _cloud.stopRemotePolling();
      return;
    }

    _cloud.resumeForActiveAccount();
    // 账号已验证后解除切号冻结，让 provider 能呈现管理员关闭备份的原因。
    if (_auth.serverConfig['backup_enabled'] == false) {
      _cloud.stopRemotePolling();
      await _cloud.syncNow();
      return;
    }
    try {
      final manualSync = force || _forceRequested;
      if (manualSync) {
        await _cloud.syncNowAndPull();
      } else {
        await _cloud.syncNow();
        // 在业务同步过程中到来的手动操作也要兑现主动拉取。
        if (_forceRequested && _isCurrent(generation, startClient)) {
          await _cloud.syncNowAndPull();
        }
      }
    } catch (e, st) {
      // 同步失败由 provider 的 lastError 呈现；这里只记录，不丢本地数据、不清标记。
      debugPrint('[backend-sync] sync failed: $e\n$st');
    }
    if (!_isCurrent(generation, startClient)) return;
    if (!_auth.state.isLoggedIn) return;
    // 手动 force 之后若用户仍关闭 autoSync，只完成这一次，不启动轮询。
    if (!_cloud.config.autoSync) return;
    _cloud.startRemotePolling();
  }

  /// 销毁/换号时调用：之后的迟到任务不会再 resume、轮询或改状态。
  void dispose() {
    _disposed = true;
    _generation++;
    _inFlight = null;
    _inFlightClient = null;
    _forceRequested = false;
  }
}
