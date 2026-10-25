import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:duoyi/services/home_widget_push_scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

HomeWidgetPushScheduler _scheduler({
  required Future<bool> Function() push,
  bool Function()? isReady,
  Future<void> Function()? ensureReady,
  bool observeLifecycle = false,
}) {
  return HomeWidgetPushScheduler(
    push: push,
    isReady: isReady ?? () => true,
    ensureReady: ensureReady ?? () async {},
    observeLifecycle: observeLifecycle,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('连续数据变化只在 2200ms 合并窗口结束后推一次', () {
    fakeAsync((async) {
      var pushes = 0;
      final scheduler = _scheduler(
        push: () async {
          pushes++;
          return true;
        },
      );

      scheduler.schedule();
      async.elapse(const Duration(milliseconds: 1000));
      scheduler.schedule();
      async.elapse(const Duration(milliseconds: 2199));
      expect(pushes, 0, reason: '合并窗口内不能写 payload');

      async.elapse(const Duration(milliseconds: 1));
      expect(pushes, 1, reason: '窗口结束后只推一次最新快照');

      async.elapse(const Duration(seconds: 30));
      expect(pushes, 1, reason: '没有新的数据变化时不再重复推送');
      scheduler.dispose();
    });
  });

  test('退到后台立即 flush，不等 2200ms 合并窗口', () {
    fakeAsync((async) {
      var pushes = 0;
      final scheduler = _scheduler(
        push: () async {
          pushes++;
          return true;
        },
        observeLifecycle: true,
      );

      scheduler.schedule();
      async.elapse(const Duration(milliseconds: 300));
      expect(pushes, 0);

      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      async.flushMicrotasks();
      expect(pushes, 1, reason: '暂停时必须立刻写入最新状态，不能等 debounce');
      expect(scheduler.hasPendingPush, isFalse);

      async.elapse(const Duration(seconds: 10));
      expect(pushes, 1, reason: '已取的合并窗口不能再补推一次');
      scheduler.dispose();
    });
  });

  test('本地数据未就绪时保留 dirty，不写空快照，hydration 后补推', () {
    fakeAsync((async) {
      var ready = false;
      var pushes = 0;
      var ensureReadyCalls = 0;
      final scheduler = _scheduler(
        push: () async {
          pushes++;
          return true;
        },
        isReady: () => ready,
        ensureReady: () async {
          ensureReadyCalls++;
          ready = true;
        },
      );

      // hydration 期间的变更（旧实现直接 return，pending 直接丢）。
      scheduler.schedule();
      async.elapse(const Duration(seconds: 5));
      expect(pushes, 0, reason: '未就绪时不能把默认空 payload 写到桌面');
      expect(scheduler.hasPendingPush, isTrue, reason: '未就绪的变更必须保留 dirty');
      expect(ensureReadyCalls, 0, reason: 'schedule 不能抢先拉起全量本地加载');

      // 启动延迟任务 / 回前台会 flush：先 await 共享 hydration 再推最新状态。
      unawaited(scheduler.flush());
      async.flushMicrotasks();
      expect(ensureReadyCalls, 1);
      expect(pushes, 1, reason: 'hydration 完成后必须补推未就绪期间的变更');
      expect(scheduler.hasPendingPush, isFalse);
      scheduler.dispose();
    });
  });

  test('写入期间的变更串行补推一次，不并发写', () {
    fakeAsync((async) {
      final gates = <Completer<bool>>[];
      var pushes = 0;
      var active = 0;
      var maxActive = 0;
      final scheduler = _scheduler(
        push: () {
          pushes++;
          active++;
          if (active > maxActive) maxActive = active;
          final gate = Completer<bool>();
          gates.add(gate);
          return gate.future.whenComplete(() => active--);
        },
      );

      unawaited(scheduler.flush(force: true));
      async.flushMicrotasks();
      expect(pushes, 1);

      // 第一次写入还没结束时到达的通知：合并成一次串行补推。
      scheduler.schedule();
      async.elapse(const Duration(seconds: 5));
      expect(pushes, 1, reason: '写入在途时不能再起一次写入');

      gates.first.complete(true);
      async.flushMicrotasks();
      expect(pushes, 2, reason: '写入期间的最新状态必须再推一次');
      expect(scheduler.hasPendingPush, isFalse);

      gates.last.complete(true);
      async.flushMicrotasks();
      expect(maxActive, 1, reason: '同一时刻只允许一次 payload 写入');
      scheduler.dispose();
    });
  });

  test('推送失败保留 dirty，不自循环重试，回前台再补推', () {
    fakeAsync((async) {
      var pushes = 0;
      var fail = true;
      final scheduler = _scheduler(
        push: () async {
          pushes++;
          return !fail;
        },
        observeLifecycle: true,
      );

      scheduler.schedule();
      async.elapse(const Duration(milliseconds: 2200));
      expect(pushes, 1);
      expect(scheduler.hasPendingPush, isTrue, reason: '推送失败必须保留 dirty 待下次补推');

      async.elapse(const Duration(seconds: 30));
      expect(pushes, 1, reason: '失败后不能在没有新通知时无休止重试');

      fail = false;
      scheduler.handleLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(pushes, 2, reason: '回到前台必须补推上次失败的数据');
      expect(scheduler.hasPendingPush, isFalse);

      scheduler.handleLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(pushes, 2, reason: '没有 dirty 时 resumed 不再推送');
      scheduler.dispose();
    });
  });

  test('推送抛错不会打断排程，等下一次生命周期恢复补推', () {
    fakeAsync((async) {
      var pushes = 0;
      var throwNext = true;
      final scheduler = _scheduler(
        push: () async {
          pushes++;
          if (throwNext) {
            throwNext = false;
            throw StateError('native channel down');
          }
          return true;
        },
        observeLifecycle: true,
      );

      scheduler.schedule();
      async.elapse(const Duration(milliseconds: 2200));
      expect(pushes, 1);
      expect(scheduler.hasPendingPush, isTrue);

      scheduler.handleLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(pushes, 2, reason: '抛错后同样保留 dirty，恢复时补推');
      expect(scheduler.hasPendingPush, isFalse);
      scheduler.dispose();
    });
  });

  test('没有待推数据时 flush 不触发平台写入', () {
    fakeAsync((async) {
      var pushes = 0;
      var ensureReadyCalls = 0;
      var ready = false;
      final scheduler = _scheduler(
        push: () async {
          pushes++;
          return true;
        },
        isReady: () => ready,
        ensureReady: () async {
          ensureReadyCalls++;
          ready = true;
        },
        observeLifecycle: true,
      );

      unawaited(scheduler.flush());
      scheduler.handleLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(pushes, 0);
      expect(
        ensureReadyCalls,
        0,
        reason: '首次 resumed 不能因为没有 dirty 就提前加载全部本地数据',
      );
      scheduler.dispose();
    });
  });

  test('dispose 取消合并窗口、解绑生命周期，之后不再推送', () {
    fakeAsync((async) {
      var pushes = 0;
      final scheduler = _scheduler(
        push: () async {
          pushes++;
          return true;
        },
        observeLifecycle: true,
      );
      expect(scheduler.observesLifecycle, isTrue);

      scheduler.schedule();
      scheduler.dispose();
      expect(scheduler.observesLifecycle, isFalse, reason: 'dispose 必须解绑观察者');

      async.elapse(const Duration(seconds: 10));
      expect(pushes, 0, reason: 'dispose 后合并窗口不能再触发推送');

      scheduler.handleLifecycleState(AppLifecycleState.paused);
      unawaited(scheduler.flush(force: true));
      async.flushMicrotasks();
      expect(pushes, 0, reason: 'dispose 后生命周期与 flush 都不再推送');
    });
  });

  test('强制 flush 等待在途写入和最新状态补推后才返回', () {
    fakeAsync((async) {
      final gates = <Completer<bool>>[];
      final snapshots = <int>[];
      var version = 1;
      var acknowledged = false;
      final scheduler = _scheduler(
        push: () {
          snapshots.add(version);
          final gate = Completer<bool>();
          gates.add(gate);
          return gate.future;
        },
      );
      unawaited(scheduler.flush(force: true));
      version = 2;
      unawaited(scheduler.flush(force: true).then((ok) => acknowledged = ok));
      expect(snapshots, [1]);
      gates.first.complete(true);
      async.flushMicrotasks();
      expect(snapshots, [1, 2]);
      expect(acknowledged, isFalse, reason: '最新快照完成前不能回执成功');
      gates.last.complete(true);
      async.flushMicrotasks();
      expect(acknowledged, isTrue);
      scheduler.dispose();
    });
  });

  test('dispose 不取消已有写入，但阻止已排队的后续补推', () {
    fakeAsync((async) {
      final gate = Completer<bool>();
      var pushes = 0;
      final scheduler = _scheduler(
        push: () {
          pushes++;
          return gate.future;
        },
      );
      unawaited(scheduler.flush(force: true));
      scheduler.schedule();
      scheduler.dispose();
      gate.complete(true);
      async.flushMicrotasks();
      expect(pushes, 1, reason: '释放后不得因旧 queued 再次写入');
    });
  });
}
