import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用真实 SharedPreferences 方法通道模拟持久化成功、false 与异常，
/// 同时检查平台数据、缓存和 Provider 内存，避免失败修改被后续全量写入复活。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final storage = <String, Object>{};
  var rejectWrites = false;
  Object? writeError;

  setUp(() {
    SharedPreferences.resetStatic();
    storage.clear();
    rejectWrites = false;
    writeError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') return Map<String, Object>.of(storage);
          if (writeError != null) throw writeError!;
          if (rejectWrites) return false;
          final arguments = call.arguments as Map<dynamic, dynamic>?;
          if (call.method == 'clear') {
            storage.clear();
          } else if (call.method == 'remove') {
            storage.remove(arguments?['key']);
          } else if (call.method.startsWith('set')) {
            storage[arguments!['key'] as String] = arguments['value'] as Object;
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    SharedPreferences.resetStatic();
  });

  test('写入返回 false 后回滚内存，撤销值不会被其它任务写入复活', () async {
    final provider = TodoProvider();
    addTearDown(provider.dispose);
    await provider.addTodo(TodoItem(id: 'stored-false', title: '初始标题'));
    rejectWrites = true;
    await expectLater(
      provider.updateTodo(
        'stored-false',
        provider.todos.single.copyWith(title: '未落盘的标题'),
        waitForReminderSync: false,
      ),
      throwsA(isA<StateError>()),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(provider.todos.single.title, '初始标题');
    expect(prefs.getString('todos'), contains('初始标题'));
    expect(prefs.getString('todos'), isNot(contains('未落盘的标题')));

    rejectWrites = false;
    await provider.addTodo(TodoItem(id: 'other', title: '另一个任务'));
    await prefs.reload();
    expect(prefs.getString('todos'), contains('另一个任务'));
    expect(prefs.getString('todos'), contains('初始标题'));
    expect(prefs.getString('todos'), isNot(contains('未落盘的标题')));
  });

  test('写入抛异常后回滚内存，恢复后可重试成功', () async {
    final provider = TodoProvider();
    addTearDown(provider.dispose);
    await provider.addTodo(TodoItem(id: 'stored-throw', title: '初始标题'));
    writeError = PlatformException(code: 'disk_full');
    await expectLater(
      provider.updateTodo(
        'stored-throw',
        provider.todos.single.copyWith(title: '写入异常标题'),
        waitForReminderSync: false,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(provider.todos.single.title, '初始标题');
    writeError = null;
    await provider.updateTodo(
      'stored-throw',
      provider.todos.single.copyWith(title: '重试成功'),
      waitForReminderSync: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(provider.todos.single.title, '重试成功');
    expect(prefs.getString('todos'), contains('重试成功'));
    expect(prefs.getString('todos'), isNot(contains('写入异常标题')));
  });

  test('账号本地状态重置会清除失败编辑草稿', () {
    final provider = TodoProvider();
    addTearDown(provider.dispose);
    provider.preserveDetailDraft(
      TodoItem(id: 'draft', title: '账号私有草稿'),
      timeTargetText: '25',
    );
    provider.resetLocalState();
    expect(provider.takeDetailDraft('draft'), isNull);
  });
}
