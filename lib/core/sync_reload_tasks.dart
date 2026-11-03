import 'dart:async';

/// 按固定批次串行执行「同步后重载」任务，并保证所有任务都跑完。
///
/// 云同步回写后的每个 collection 重载彼此独立：任一任务失败——包括返回
/// `Future` 之前就同步 throw 的情形（例如 todo 本地水合失败）——都不能中断
/// 后续 collection 的重载，否则用户会看到一半集合已刷新、另一半仍停留在旧值。
///
/// 因此这里捕获每个任务的失败后继续执行剩余任务，等全部结束后再以
/// [Error.throwWithStackTrace] 抛出**第一个**失败的原始 error 与 stack：
/// 调用方（`onSynced`）据此判定同步失败，不会被吞成“同步成功”。
///
/// - 同批任务并行启动，批与批之间 `await yieldBetweenBatches?.call()`；
/// - [batchSize] 必须为正数，否则抛 [ArgumentError]（不会执行任何任务）。
Future<void> runSyncReloadTasksInBatches(
  List<Future<void> Function()> tasks, {
  int batchSize = 1,
  Future<void> Function()? yieldBetweenBatches,
}) async {
  if (batchSize <= 0) {
    throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
  }

  Object? firstError;
  StackTrace? firstStackTrace;

  Future<void> runTask(Future<void> Function() task) async {
    try {
      await task();
    } catch (error, stackTrace) {
      // 保留首个失败：后续失败只影响各自任务，不覆盖原始 error / stack。
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  for (var i = 0; i < tasks.length; i += batchSize) {
    final end = (i + batchSize).clamp(0, tasks.length);
    await Future.wait(<Future<void>>[
      for (var j = i; j < end; j++) runTask(tasks[j]),
    ]);
    if (end < tasks.length) {
      await yieldBetweenBatches?.call();
    }
  }

  final error = firstError;
  final stackTrace = firstStackTrace;
  if (error != null && stackTrace != null) {
    Error.throwWithStackTrace(error, stackTrace);
  }
}
