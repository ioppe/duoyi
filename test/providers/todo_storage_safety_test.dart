import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 测试专用：替换 prefs 平台实现，在损坏备份写入处做确定性门控（不新增依赖）。
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  test(
    'TodoProvider skips corrupt persisted records and rewrites storage',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': '[123, "bad-record"]',
      });

      final provider = TodoProvider();
      await provider.loadFromStorage();

      expect(provider.todos, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), '[]');
      expect(
        prefs.getKeys().where((key) => key.startsWith('todos_corrupt_backup_')),
        isNotEmpty,
      );
    },
  );

  test('TodoProvider hydrates storage before first write', () async {
    final existing = TodoItem(
      id: 'existing',
      title: '旧待办',
      date: DateTime(2026, 6, 5),
      createdAt: DateTime(2026, 6, 5, 8),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': jsonEncode([existing.toJson()]),
    });

    final provider = TodoProvider();
    await provider.addTodo(
      TodoItem(
        id: 'quick',
        title: '快捷待办',
        date: DateTime(2026, 6, 5),
        createdAt: DateTime(2026, 6, 5, 9),
      ),
    );

    expect(
      provider.todos.map((todo) => todo.id),
      containsAll(['existing', 'quick']),
    );
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
    expect(
      stored
          .cast<Map<dynamic, dynamic>>()
          .map((raw) => raw['id'] as String)
          .toSet(),
      {'existing', 'quick'},
    );
  });

  test(
    'forced loadFromStorage picks up cloud-synced todos and keeps them',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = TodoProvider();
      await provider.loadFromStorage();
      final local = TodoItem(
        id: 'local-1',
        title: '本地新建',
        date: DateTime(2026, 9, 30),
      );
      await provider.addTodo(local);

      // 模拟云同步回写：同步应答把另一台设备的任务合并进本地存储。
      final remote = TodoItem(
        id: 'remote-1',
        title: '云端任务',
        date: DateTime(2026, 9, 30),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'todos',
        jsonEncode([local.toJson(), remote.toJson()]),
      );

      await provider.loadFromStorage(force: true);

      expect(
        provider.todos.map((todo) => todo.id),
        containsAll(['local-1', 'remote-1']),
      );

      // 关键回归：强制重读之后再做本地写入，不得把同步结果整表覆盖掉。
      await provider.updateTodo(
        'local-1',
        provider.todos
            .firstWhere((todo) => todo.id == 'local-1')
            .copyWith(title: '本地编辑'),
      );
      final storedAfter =
          jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(
        storedAfter.cast<Map<dynamic, dynamic>>().map((raw) => raw['id']),
        containsAll(['local-1', 'remote-1']),
      );
    },
  );

  test(
    'loadFromStorage collapses duplicate ids keeping the newest record',
    () async {
      final older = TodoItem(
        id: 'dup',
        title: '旧版本',
        date: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30, 8),
      );
      final newer = TodoItem(
        id: 'dup',
        title: '新版本',
        date: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30, 9),
      );
      final other = TodoItem(
        id: 'other',
        title: '其他任务',
        date: DateTime(2026, 9, 30),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': jsonEncode([older.toJson(), newer.toJson(), other.toJson()]),
      });

      final provider = TodoProvider();
      await provider.loadFromStorage();

      expect(provider.todos, hasLength(2));
      expect(
        provider.todos.firstWhere((todo) => todo.id == 'dup').title,
        '新版本',
      );
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(stored, hasLength(2));
    },
  );

  test(
    'forced loadFromStorage on rewrite-needed storage completes without deadlock',
    () async {
      // 回归：强制重读占用 _storageWriteQueue 尾部，损坏/重复存储触发的
      // 重写若再走队列会与自身互相等待（历史死锁），必须内联落盘。
      final older = TodoItem(
        id: 'dup',
        title: '旧版本',
        date: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30, 8),
      );
      final newer = TodoItem(
        id: 'dup',
        title: '新版本',
        date: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30, 9),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        // 合法数组内的重复 id + 坏记录：分别经 dedupe 与逐条容错触发重写。
        'todos': jsonEncode([older.toJson(), newer.toJson(), 123]),
      });

      final provider = TodoProvider();
      await provider.loadFromStorage(force: true);

      expect(provider.todos, hasLength(1));
      expect(provider.todos.single.id, 'dup');
      expect(provider.todos.single.title, '新版本');
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(stored, hasLength(1));
      expect(
        prefs.getKeys().where((key) => key.startsWith('todos_corrupt_backup_')),
        isNotEmpty,
      );
      // 死锁回归的另一面：强制重读完成后，后续写入必须仍能正常排队落盘。
      await provider.addTodo(
        TodoItem(id: 'after', title: '重读后新增', date: DateTime(2026, 10, 1)),
      );
      final storedAfter =
          jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(
        storedAfter.cast<Map<dynamic, dynamic>>().map((raw) => raw['id']),
        containsAll(['dup', 'after']),
      );
    },
  );

  test(
    'large corrupt storage decodes off the main isolate and keeps valid records',
    () async {
      // 超过 _isolateDecodeMinChars 的大存储必须走后台解码路径，
      // 且逐条容错语义（跳过坏记录、备份、重写）保持一致。
      final valid = List.generate(900, (i) {
        return TodoItem(
          id: 'iso-$i',
          title: '隔离解码验证任务 $i',
          date: DateTime(2026, 9, 30),
        ).toJson();
      });
      final raw = jsonEncode([...valid, 'bad-record', 123]);
      expect(raw.length, greaterThan(60000));
      SharedPreferences.setMockInitialValues(<String, Object>{'todos': raw});

      final provider = TodoProvider();
      await provider.loadFromStorage();

      expect(provider.todos, hasLength(900));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((key) => key.startsWith('todos_corrupt_backup_')),
        isNotEmpty,
      );
      final rewritten = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(rewritten, hasLength(900));
    },
  );

  test(
    'hydrates storage and reports isHydrated only after a complete read',
    () async {
      final seeded = <TodoItem>[
        TodoItem(
          id: 'seed-a',
          title: '水合任务 A',
          date: DateTime(2026, 6, 5),
          createdAt: DateTime(2026, 6, 5, 8),
          updatedAt: DateTime(2026, 6, 5, 8),
        ),
        TodoItem(
          id: 'seed-b',
          title: '水合任务 B',
          date: DateTime(2026, 6, 6),
          createdAt: DateTime(2026, 6, 6, 9),
          updatedAt: DateTime(2026, 6, 6, 9),
        ),
      ];
      final raw = jsonEncode(seeded.map((todo) => todo.toJson()).toList());
      SharedPreferences.setMockInitialValues(<String, Object>{'todos': raw});

      final provider = TodoProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(provider.isHydrated, isFalse, reason: '构造后尚未读取本地存储。');
      expect(provider.todos, isEmpty);

      await provider.loadFromStorage();

      expect(provider.isHydrated, isTrue);
      expect(
        provider.todos.map((todo) => todo.id),
        unorderedEquals(<String>['seed-a', 'seed-b']),
      );
      expect(notifications, 1, reason: '一次完整水合只发布一次。');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), raw, reason: '合法存储不应被读取路径改写。');

      // 合法空列表同样算完成水合：否则云同步空变更集会反复补读。
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final emptyProvider = TodoProvider();
      await emptyProvider.loadFromStorage();
      expect(emptyProvider.isHydrated, isTrue);
      expect(emptyProvider.todos, isEmpty);
    },
  );

  test('concurrent loads coalesce into one complete publish', () async {
    final seeded = List<TodoItem>.generate(
      3,
      (i) => TodoItem(
        id: 'co-$i',
        title: '并发任务 $i',
        date: DateTime(2026, 7, 1 + i),
        createdAt: DateTime(2026, 7, 1 + i, 8),
        updatedAt: DateTime(2026, 7, 1 + i, 8),
      ),
    );
    final raw = jsonEncode(seeded.map((todo) => todo.toJson()).toList());
    SharedPreferences.setMockInitialValues(<String, Object>{'todos': raw});

    final provider = TodoProvider();
    var notifications = 0;
    final publishedLengths = <int>[];
    provider.addListener(() {
      notifications++;
      publishedLengths.add(provider.todos.length);
    });

    await Future.wait(<Future<void>>[
      provider.loadFromStorage(),
      provider.loadFromStorage(),
    ]);

    expect(provider.isHydrated, isTrue);
    expect(notifications, 1, reason: '并发普通读取必须合流，只发布一次。');
    expect(publishedLengths, <int>[3], reason: '首次可见状态就是完整列表，不能先空后满。');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), raw, reason: '并发读取不应改写存储。');
  });

  test(
    'resetLocalState discards stale generation load and keeps isHydrated false',
    () async {
      final staleTodo = TodoItem(
        id: 'old-account',
        title: '旧账号任务',
        date: DateTime(2026, 8, 1),
        createdAt: DateTime(2026, 8, 1, 8),
        updatedAt: DateTime(2026, 8, 1, 8),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': jsonEncode([staleTodo.toJson()]),
      });

      final provider = TodoProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      final staleLoad = provider.loadFromStorage();
      // 账号切换：同步作废在途读取，旧代际结果必须被丢弃。
      provider.resetLocalState();
      await staleLoad;

      expect(notifications, 1, reason: '此处仅 resetLocalState 自身发布一次。');
      expect(provider.isHydrated, isFalse, reason: '旧代际读取不得复活水合标记。');
      expect(provider.todos, isEmpty, reason: '旧账号列表不得被写回内存。');

      final newTodo = TodoItem(
        id: 'new-account',
        title: '新账号任务',
        date: DateTime(2026, 8, 2),
        createdAt: DateTime(2026, 8, 2, 8),
        updatedAt: DateTime(2026, 8, 2, 8),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', jsonEncode([newTodo.toJson()]));

      await provider.loadFromStorage();

      expect(provider.isHydrated, isTrue);
      expect(provider.todos.map((todo) => todo.id), <String>['new-account']);
    },
  );

  test(
    'large corrupt cache rewrite never overwrites a cloud snapshot written mid-repair',
    () async {
      final oldItems = List<TodoItem>.generate(
        900,
        (i) => TodoItem(
          id: 'old-$i',
          title: '旧缓存任务 $i',
          date: DateTime(2026, 9, 30),
          createdAt: DateTime(2026, 9, 30, 8),
          updatedAt: DateTime(2026, 9, 30, 8),
        ),
      );
      // 体积超过 isolate 解码阈值且含坏记录：必须走真实 compute 并触发重写。
      final oldRaw = jsonEncode([
        ...oldItems.map((todo) => todo.toJson()),
        123,
      ]);
      expect(oldRaw.length, greaterThan(60000));

      final remoteItems = <TodoItem>[
        TodoItem(
          id: 'remote-1',
          title: '云端任务 1',
          date: DateTime(2026, 10, 1),
          createdAt: DateTime(2026, 10, 1, 8),
          updatedAt: DateTime(2026, 10, 1, 8),
        ),
        TodoItem(
          id: 'remote-2',
          title: '云端任务 2',
          date: DateTime(2026, 10, 2),
          createdAt: DateTime(2026, 10, 2, 8),
          updatedAt: DateTime(2026, 10, 2, 8),
        ),
      ];
      final remoteRaw = jsonEncode(
        remoteItems.map((todo) => todo.toJson()).toList(),
      );

      final store = _GatedTodosPrefsStore.withData(<String, Object>{
        'flutter.todos': oldRaw,
      });
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesStorePlatform.instance = store;
      store.backupWriteGate = Completer<void>();

      final provider = TodoProvider();
      final prefs = await SharedPreferences.getInstance();

      final load = provider.loadFromStorage();
      await store.backupWriteStarted.future;
      // 解析（真实 compute）已结束、正在写损坏备份：还没有 publish 任何快照。
      expect(provider.isHydrated, isFalse, reason: '水合完成前不得 publish。');

      // 云同步不经过 Provider 的写入队列，直接在同一个 await 边界写新快照。
      await prefs.setString('todos', remoteRaw);
      store.backupWriteGate!.complete();
      await load;

      expect(provider.isHydrated, isTrue);
      expect(
        provider.todos.map((todo) => todo.id),
        unorderedEquals(<String>['remote-1', 'remote-2']),
        reason: '必须发布云端最新快照，不能停留在旧缓存。',
      );
      expect(
        prefs.getString('todos'),
        remoteRaw,
        reason: '旧损坏缓存的重写不得反写覆盖云端新快照。',
      );
      expect(
        prefs.getKeys().where((key) => key.startsWith('todos_corrupt_backup_')),
        isNotEmpty,
        reason: '旧缓存仍要留一份备份，便于事后排查。',
      );

      // 之后的本地编辑必须保留云端任务。
      await provider.updateTodo(
        'remote-1',
        provider.todos
            .firstWhere((todo) => todo.id == 'remote-1')
            .copyWith(title: '本地编辑'),
      );
      final stored = (jsonDecode(prefs.getString('todos')!) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        stored.map((raw) => raw['id']),
        unorderedEquals(<String>['remote-1', 'remote-2']),
      );
      expect(
        stored.firstWhere((raw) => raw['id'] == 'remote-1')['title'],
        '本地编辑',
      );
    },
  );

  test(
    'force reload queued during a cloud replace publishes the remote snapshot',
    () async {
      final oldItems = List<TodoItem>.generate(
        900,
        (i) => TodoItem(
          id: 'old-$i',
          title: '旧缓存任务 $i',
          date: DateTime(2026, 9, 30),
          createdAt: DateTime(2026, 9, 30, 8),
          updatedAt: DateTime(2026, 9, 30, 8),
        ),
      );
      final oldRaw = jsonEncode([
        ...oldItems.map((todo) => todo.toJson()),
        123,
      ]);
      final remoteRaw = jsonEncode([
        TodoItem(
          id: 'remote-force',
          title: '云端任务',
          date: DateTime(2026, 10, 3),
          createdAt: DateTime(2026, 10, 3, 8),
          updatedAt: DateTime(2026, 10, 3, 8),
        ).toJson(),
      ]);

      final store = _GatedTodosPrefsStore.withData(<String, Object>{
        'flutter.todos': oldRaw,
      });
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesStorePlatform.instance = store;
      store.backupWriteGate = Completer<void>();

      final provider = TodoProvider();
      final prefs = await SharedPreferences.getInstance();

      final load = provider.loadFromStorage();
      // 强制重读排在普通读取之后：两者都必须落在云端新快照上。
      final forced = provider.loadFromStorage(force: true);
      await store.backupWriteStarted.future;
      expect(provider.isHydrated, isFalse);

      await prefs.setString('todos', remoteRaw);
      store.backupWriteGate!.complete();
      await load;
      await forced;

      expect(provider.isHydrated, isTrue);
      expect(provider.todos.map((todo) => todo.id), <String>['remote-force']);
      expect(prefs.getString('todos'), remoteRaw, reason: '强制重读结束后存储仍是云端快照。');
    },
  );

  test('unstable storage blocks mutation until hydration can finish', () async {
    String snapshot(int revision) => jsonEncode([
      TodoItem(
        id: 'remote-$revision',
        title: '云端快照 $revision',
        date: DateTime(2026, 10, 3),
        createdAt: DateTime(2026, 10, 3, 8),
        updatedAt: DateTime(2026, 10, 3, 8),
      ).toJson(),
      123,
    ]);
    final store = _GatedTodosPrefsStore.withData(<String, Object>{
      'flutter.todos': snapshot(0),
    });
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    var revision = 0;
    store.onBackupWrite = () async {
      await prefs.setString('todos', snapshot(++revision));
    };
    final provider = TodoProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);
    final added = TodoItem(
      id: 'new-local',
      title: '待水合完成后新增',
      date: DateTime(2026, 10, 3),
    );

    await expectLater(provider.addTodo(added), throwsStateError);

    expect(provider.isHydrated, isFalse);
    expect(notifications, 0);
    expect(revision, greaterThan(1));
    expect(prefs.getString('todos'), snapshot(revision));
    expect(provider.todos.any((todo) => todo.id == added.id), isFalse);

    // 外部替换停止后，新的读取可成功完成；本地写入仍保留最新云端记录。
    store.onBackupWrite = null;
    await provider.addTodo(added);
    expect(provider.isHydrated, isTrue);
    final stored = (jsonDecode(prefs.getString('todos')!) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      stored.map((raw) => raw['id']),
      unorderedEquals(<String>['remote-$revision', 'new-local']),
    );
  });
}

/// 可控的 prefs 平台实现：在“损坏备份写入”处暂停，用于确定性地模拟云同步
/// 在同一 await 边界写入新快照（不依赖毫秒睡眠或速度阈值）。
class _GatedTodosPrefsStore extends InMemorySharedPreferencesStore {
  _GatedTodosPrefsStore.withData(super.data) : super.withData();

  final Completer<void> backupWriteStarted = Completer<void>();
  Completer<void>? backupWriteGate;
  Future<void> Function()? onBackupWrite;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.contains('todos_corrupt_backup_')) {
      if (!backupWriteStarted.isCompleted) {
        backupWriteStarted.complete();
      }
      final gate = backupWriteGate;
      if (gate != null && !gate.isCompleted) {
        await gate.future;
      }
      await onBackupWrite?.call();
    }
    return super.setValue(valueType, key, value);
  }
}
