import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cloud_sync_provider.dart';

/// 云同步状态的展示层控制器（UI 消费专用）。
///
/// 两个职责：
/// 1. 只读转发 [CloudSyncProvider] 的公开状态并转发其通知，供我的页
///    "云同步状态卡" watch；
/// 2. 提供**唯一**的手动同步入口 [requestSync]。同步动作本身由应用层
///    （main.dart）通过构造参数 [onSyncRequested] 注入——应用层负责先刷新
///    公共后端配置 / 账号 AI 配置，再同步业务数据。UI 层（lib/screens、
///    lib/widgets）因此只调用 `requestSync()`，不直接引用
///    CloudSyncProvider（架构守卫见 test/services/cloud_sync_provider_test.dart
///    「UI 层只经 SyncStatusController 请求同步」）。
///
/// [requestSync] 的语义：
/// - 未注入回调时安全空操作（[canSync] 为 false），不抛错；
/// - 底层 provider 已在同步时仍转交应用层，等待在途同步后兑现主动拉取；
/// - single-flight：飞行中的请求复用同一个 Future，绝不并发触发第二次回调；
/// - "同步中"覆盖整段回调耗时（[isSyncing] 同时反映手动回调与底层 provider）；
/// - 回调失败只记录布尔标记 [syncRequestFailed]，不保留异常文本，避免服务端
///   地址 / token 泄漏；卡片复用 `sync.state.failed` 文案呈现，可再次点击重试。
///   该标记在底层出现**确实更新**的成功 lastSync（且非忙、无错误）时自动清除，
///   不会因为收到任意一次通知就清除。
/// - [attach] / [detach] / [dispose] 会失效旧请求：换绑后新 source 可立即发起
///   新请求，旧回调迟到完成既不 notify，也不清除或改写新请求的忙闲/失败状态
///   （代际号 + 归属校验）。
class SyncStatusController extends ChangeNotifier {
  SyncStatusController({
    CloudSyncProvider? source,
    Future<void> Function()? onSyncRequested,
  }) : _onSyncRequested = onSyncRequested {
    if (source != null) attach(source);
  }

  CloudSyncProvider? _source;
  final Future<void> Function()? _onSyncRequested;
  bool _forwarding = false;
  Future<void>? _requestInFlight;
  bool _requesting = false;
  bool _requestFailed = false;

  /// 手动请求失败时底层最后一次成功时间，用于识别"确实更新"的成功同步。
  DateTime? _manualFailureLastSync;
  bool _disposed = false;
  int _generation = 0;

  /// 绑定底层 provider 并转发其状态通知。
  ///
  /// 换绑会失效旧请求：旧回调迟到完成后不再占用忙闲状态，也不改写新 source
  /// 的失败标记；新 source 可立即发起新请求。
  void attach(CloudSyncProvider provider) {
    if (_disposed || identical(_source, provider)) return;
    _source?.removeListener(_forward);
    _source = provider;
    provider.addListener(_forward);
    _invalidatePendingRequest();
    _notify();
  }

  void detach() {
    _source?.removeListener(_forward);
    _source = null;
    _invalidatePendingRequest();
    _notify();
  }

  /// 让当前飞行中的请求失效：递增代际号并释放忙闲/失败状态。
  ///
  /// 旧请求自己的 Future 仍会正常完成；其收尾时因代际或归属不匹配，
  /// 不会清除新请求的忙闲状态或失败标记。
  void _invalidatePendingRequest() {
    _generation++;
    _requestInFlight = null;
    _requesting = false;
    _requestFailed = false;
    _manualFailureLastSync = null;
  }

  void _forward() {
    if (_forwarding) return;
    _forwarding = true;
    try {
      _clearStaleManualFailure();
      _notify();
    } finally {
      _forwarding = false;
    }
  }

  /// 底层出现确实更新的成功同步时清除旧的手动失败标记。
  ///
  /// 只在"非同步中、无底层错误、lastSync 晚于失败时刻记录的基线"时清除；
  /// 任意一次通知都不足以清除，避免失败提示被无关通知抹掉。
  void _clearStaleManualFailure() {
    if (!_requestFailed || _requesting) return;
    final baseline = _manualFailureLastSync;
    if (baseline == null) return;
    final source = _source;
    if (source == null || source.isSyncing || source.lastError != null) return;
    if (!source.config.lastSync.isAfter(baseline)) return;
    _requestFailed = false;
    _manualFailureLastSync = null;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 是否注入了手动同步动作；同步期间也保持下拉刷新组件挂载。
  bool get hasSyncAction => !_disposed && _onSyncRequested != null;

  /// 卡片是否可点击：有同步动作且当前不处于同步中。
  bool get canSync => hasSyncAction && !isSyncing;

  /// 请求一次同步（经应用层注入的回调）。
  ///
  /// 未注入回调时安全返回；底层同步中的请求由应用层等待后执行。
  /// 重复调用会合流到同一个 Future，因此不会并发触发回调。
  /// 失败通过 [syncRequestFailed] 观察，异常本身不被转抛（其文本可能含服务器
  /// 地址 / token）。
  Future<void> requestSync() {
    if (_disposed) return Future<void>.value();
    final inFlight = _requestInFlight;
    if (inFlight != null) return inFlight;
    final request = _onSyncRequested;
    if (request == null) return Future<void>.value();

    final completer = Completer<void>();
    _requestInFlight = completer.future;
    _requesting = true;
    _requestFailed = false;
    _manualFailureLastSync = null;
    _notify();
    if (_disposed) {
      // 通知期间被 dispose：不再触发回调。
      _requestInFlight = null;
      _requesting = false;
      completer.complete();
      return completer.future;
    }
    unawaited(_runRequest(request, _generation, completer));
    return completer.future;
  }

  Future<void> _runRequest(
    Future<void> Function() request,
    int generation,
    Completer<void> completer,
  ) async {
    var failed = false;
    try {
      await request();
    } catch (_) {
      // 只记录失败事实；异常文本一律丢弃。
      failed = true;
    }
    // 只有"仍是当前飞行请求且代际匹配"时才收尾：换绑/解绑后迟到的旧请求
    // 既不清忙闲状态，也不覆盖新请求的失败标记。
    final isCurrent =
        !_disposed &&
        generation == _generation &&
        identical(_requestInFlight, completer.future);
    if (isCurrent) {
      _requestInFlight = null;
      _requesting = false;
      _requestFailed = failed;
      _manualFailureLastSync = failed ? lastSync : null;
      _notify();
    }
    if (!completer.isCompleted) completer.complete();
  }

  /// 上次成功同步时间；从未同步时为 epoch 0（[hasEverSynced] 为 false）。
  DateTime get lastSync =>
      _source?.config.lastSync ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// 同步中：手动请求（含回调整段耗时）或底层 provider 自动同步任一进行中。
  bool get isSyncing => _requesting || (_source?.isSyncing ?? false);

  /// 上一次手动同步请求是否失败（不携带异常文本）。
  ///
  /// 底层之后出现确实更新的成功同步时会自动清除（见类文档）。
  bool get syncRequestFailed => _requestFailed;

  String? get lastError => _source?.lastError;

  bool get hasEverSynced => _source?.hasEverSynced ?? false;

  bool get hasPendingChanges => _source?.hasPendingChanges ?? false;

  @override
  void dispose() {
    _disposed = true;
    _invalidatePendingRequest();
    _source?.removeListener(_forward);
    _source = null;
    super.dispose();
  }
}
