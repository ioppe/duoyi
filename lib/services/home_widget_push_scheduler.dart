import 'dart:async';

import 'package:flutter/widgets.dart';

/// 桌面小组件快照推送的单一串行排程器。
///
/// 职责边界：只负责“什么时候把内存里的最新状态写进小组件 payload 并刷新原生
/// 组件”，不负责重算 payload（仍是 `main.dart` 的 `_pushHomeWidget`）。
///
/// 生产链路（`main.dart` 启动时创建、进程级存活）：
/// 1. 数据变化：`schedule()` 只把状态标记为 dirty，并按 [debounce] 合并；
/// 2. 本地数据还没 hydrate 完：同样只保留 dirty，不写空快照；
/// 3. 退到后台 / 暂停 / 退出（inactive / hidden / paused / detached）：
///    `flush()` 立即取消合并窗口并写入最新状态，避免最后一次编辑停在
///    debounce 窗口里随进程被系统回收；
/// 4. 回到前台（resumed）：只有在仍有 dirty（含上次失败）时才补推，未就绪则
///    await 一次共享 hydration，不会为了首次 resumed 提前拉起全部本地数据；
/// 5. 写入失败（原生 0 命中 / 抛错）：保留 dirty，等下一次 `schedule()` 或
///    生命周期恢复再重试，不在排程器内部无休止重试。
class HomeWidgetPushScheduler with WidgetsBindingObserver {
  HomeWidgetPushScheduler({
    required Future<bool> Function() push,
    required bool Function() isReady,
    required Future<void> Function() ensureReady,
    Duration debounce = defaultDebounce,
    bool observeLifecycle = false,
  }) : _push = push,
       _isReady = isReady,
       _ensureReady = ensureReady,
       _debounce = debounce {
    if (observeLifecycle) {
      // 只挂观察者，不覆盖 SystemChannels.lifecycle 的既有 handler。
      WidgetsBinding.instance.addObserver(this);
      _lifecycleAttached = true;
    }
  }

  /// 默认合并窗口：连续数据变化只推一次快照（与旧 `main.dart` 排程一致）。
  static const Duration defaultDebounce = Duration(milliseconds: 2200);

  final Future<bool> Function() _push;
  final bool Function() _isReady;
  final Future<void> Function() _ensureReady;
  final Duration _debounce;

  /// 串行写入是否在途（旧 `main.dart` 排程字段迁入，语义不变：同一时刻只有
  /// 一次 payload 写入 + 原生刷新，并发通知只会合并成一次串行补推）。
  var homeWidgetPushInFlight = false;

  /// 写入期间又收到通知：本次写入结束后必须再串行补推一次最新状态。
  var homeWidgetPushQueued = false;

  Timer? _debounceTimer;
  Future<bool>? _inFlightPush;
  bool _dirty = false;
  bool _disposed = false;
  bool _lifecycleAttached = false;

  /// 是否还有待推数据（未就绪时的变更也计入）。
  @visibleForTesting
  bool get hasPendingPush => _dirty;

  /// 是否仍挂在 [WidgetsBinding] 生命周期观察者上。
  @visibleForTesting
  bool get observesLifecycle => _lifecycleAttached;

  /// 标记小组件数据已变化，并按 [debounce] 合并推送。
  void schedule() {
    if (_disposed) return;
    _dirty = true;
    if (homeWidgetPushInFlight) {
      // 写入在途：交给串行循环补推，不再叠一个 debounce 定时器。
      homeWidgetPushQueued = true;
      return;
    }
    if (!_isReady()) {
      // 本地数据还没 hydrate 完：保留 dirty，避免把默认空 payload 写到桌面。
      // 就绪后会由下一次 schedule()/flush()（启动延迟任务、生命周期恢复）
      // 补推，不会在这里抢先触发全量本地加载。
      return;
    }
    _armDebounce();
  }

  /// 立即推送最新快照，返回本次推送是否成功。
  ///
  /// [force] 用于即便没有 dirty 也要写一次的场景；退出 / 恢复走默认值，
  /// 没有待推数据时直接返回 true，不做无谓的平台调用。
  Future<bool> flush({bool force = false}) {
    if (_disposed) return Future<bool>.value(false);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final inFlight = _inFlightPush;
    if (inFlight != null) {
      // 已有写入在途：合并成一次串行补推，共用同一个 future，不并发刷原生。
      homeWidgetPushQueued = true;
      return inFlight;
    }
    if (!force && !_dirty) return Future<bool>.value(true);
    return _ensureReadyThenPush();
  }

  Future<bool> _ensureReadyThenPush() async {
    _dirty = true;
    if (!_isReady()) {
      try {
        await _ensureReady();
      } catch (e, st) {
        debugPrint('[HomeWidget] ensure local storage ready failed: $e\n$st');
      }
      if (_disposed) return false;
      if (!_isReady()) {
        debugPrint('[HomeWidget] push deferred: local storage not ready');
        return false;
      }
    }
    return _startPush();
  }

  Future<bool> _startPush() {
    final existing = _inFlightPush;
    if (existing != null) return existing;
    final completer = Completer<bool>();
    _inFlightPush = completer.future;
    homeWidgetPushInFlight = true;
    unawaited(_runPushCycle(completer));
    return completer.future;
  }

  /// 串行写入循环：写入期间到达的通知会再补推一次，不丢最后一次改动。
  Future<void> _runPushCycle(Completer<bool> completer) async {
    var ok = true;
    try {
      do {
        homeWidgetPushQueued = false;
        _dirty = false;
        try {
          ok = await _push();
        } catch (e, st) {
          debugPrint('[HomeWidget] push threw: $e\n$st');
          ok = false;
        }
        if (!ok) {
          // 保留 dirty 等下一次 schedule()/生命周期恢复，避免失败后 tight loop。
          _dirty = true;
          break;
        }
      } while (homeWidgetPushQueued && !_disposed);
    } finally {
      // 与最后一次 await 处于同一同步段收尾，收尾瞬间到达的通知不会被吞掉。
      homeWidgetPushInFlight = false;
      _inFlightPush = null;
      completer.complete(ok);
    }
  }

  void _armDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      _debounceTimer = null;
      unawaited(flush());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleState(state);
  }

  /// 生命周期入口（[didChangeAppLifecycleState] 转发，便于单测直接调用）。
  void handleLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // 退到后台 / 被系统回收前把合并窗口里的最后一次改动立即落盘。
        // 未就绪时会先 await 一次共享 hydration（幂等）。
        unawaited(flush());
        return;
      case AppLifecycleState.resumed:
        // 只补推真正待推的数据，避免首次 resumed 提前拉起全量本地数据。
        if (!_dirty) return;
        unawaited(flush());
        return;
    }
  }

  /// 停止排程：取消合并窗口、解绑生命周期观察者，之后不再触发任何推送。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
  }
}
