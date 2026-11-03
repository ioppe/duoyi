import 'package:duoyi/core/sync_reload_tasks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首个任务失败后其余任务仍全部执行，并抛出原始 error 与 stack', () async {
    final executed = <String>[];
    final failure = StateError('first reload failed');
    StackTrace? capturedStack;

    Future<void> failing() async {
      executed.add('first');
      try {
        throw failure;
      } catch (_, stackTrace) {
        capturedStack = stackTrace;
        rethrow;
      }
    }

    Object? thrown;
    StackTrace? thrownStack;
    try {
      await runSyncReloadTasksInBatches(<Future<void> Function()>[
        failing,
        () async => executed.add('second'),
        () async => executed.add('third'),
      ]);
    } catch (error, stackTrace) {
      thrown = error;
      thrownStack = stackTrace;
    }

    expect(executed, <String>[
      'first',
      'second',
      'third',
    ], reason: '失败不能中断后续集合重载');
    expect(identical(thrown, failure), isTrue, reason: '必须抛出原始 error 实例');
    expect(capturedStack, isNotNull);
    expect(
      identical(thrownStack, capturedStack),
      isTrue,
      reason: '必须保留原始 stack，不能被重新包装',
    );
  });

  test('任务在返回 Future 之前同步 throw 时同样继续执行其余任务', () async {
    final executed = <String>[];
    final failure = ArgumentError('synchronous boom');

    Object? thrown;
    try {
      await runSyncReloadTasksInBatches(<Future<void> Function()>[
        () {
          executed.add('sync-throw');
          throw failure;
        },
        () async => executed.add('after-sync-throw'),
      ]);
    } catch (error) {
      thrown = error;
    }

    expect(executed, <String>['sync-throw', 'after-sync-throw']);
    expect(identical(thrown, failure), isTrue);
  });

  test('多个任务失败时保留第一个失败，不让后失败覆盖', () async {
    final first = StateError('first');
    final second = StateError('second');
    final executed = <String>[];

    Object? thrown;
    try {
      await runSyncReloadTasksInBatches(<Future<void> Function()>[
        () async {
          executed.add('a');
          throw first;
        },
        () async {
          executed.add('b');
          throw second;
        },
        () async => executed.add('c'),
      ]);
    } catch (error) {
      thrown = error;
    }

    expect(executed, <String>['a', 'b', 'c']);
    expect(identical(thrown, first), isTrue);
  });

  test('批次失败后仍执行后续批次，并在批之间 yield', () async {
    final executed = <String>[];
    var yields = 0;

    await runSyncReloadTasksInBatches(
      <Future<void> Function()>[
        () async {
          executed.add('a');
          throw StateError('batch one failed');
        },
        () async => executed.add('b'),
        () async => executed.add('c'),
        () async => executed.add('d'),
      ],
      batchSize: 2,
      yieldBetweenBatches: () async {
        yields += 1;
      },
    ).catchError((Object _) {});

    expect(executed, <String>['a', 'b', 'c', 'd']);
    expect(yields, 1, reason: '两批之间 yield 一次，最后一批之后不再 yield');
  });

  test('成功路径同批并行、批之间串行，yield 次数等于批间隔', () async {
    final started = <int>[];
    var running = 0;
    var maxRunning = 0;
    var yields = 0;

    await runSyncReloadTasksInBatches(
      <Future<void> Function()>[
        for (var i = 0; i < 4; i++)
          () async {
            started.add(i);
            running += 1;
            if (running > maxRunning) maxRunning = running;
            await Future<void>.delayed(Duration.zero);
            running -= 1;
          },
      ],
      batchSize: 2,
      yieldBetweenBatches: () async {
        yields += 1;
      },
    );

    expect(started, <int>[0, 1, 2, 3], reason: '批内顺序启动，批之间按批次推进');
    expect(maxRunning, 2, reason: 'batchSize=2 时同批并行、不同批不重叠');
    expect(yields, 1);
  });

  test('batchSize 为 1 时严格串行', () async {
    var running = 0;
    var maxRunning = 0;
    var yields = 0;

    await runSyncReloadTasksInBatches(
      <Future<void> Function()>[
        for (var i = 0; i < 3; i++)
          () async {
            running += 1;
            if (running > maxRunning) maxRunning = running;
            await Future<void>.delayed(Duration.zero);
            running -= 1;
          },
      ],
      yieldBetweenBatches: () async {
        yields += 1;
      },
    );

    expect(maxRunning, 1, reason: '默认 batchSize=1，任务之间不并行');
    expect(yields, 2);
  });

  for (final invalidBatchSize in <int>[0, -1]) {
    test('batchSize=$invalidBatchSize 直接拒绝且不执行任何任务', () async {
      var executed = false;
      await expectLater(
        runSyncReloadTasksInBatches(<Future<void> Function()>[
          () async => executed = true,
        ], batchSize: invalidBatchSize),
        throwsA(isA<ArgumentError>()),
      );
      expect(executed, isFalse);
    });
  }

  test('空任务列表是同步成功', () async {
    await runSyncReloadTasksInBatches(<Future<void> Function()>[]);
    await runSyncReloadTasksInBatches(
      <Future<void> Function()>[],
      batchSize: 4,
      yieldBetweenBatches: () async {},
    );
  });
}
