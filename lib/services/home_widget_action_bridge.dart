import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';

/// 主 isolate 对一条桌面动作的处理结果。
///
/// 跨 isolate 只传 [name] 字符串，避免把业务类型或异常对象发出去。
enum HomeWidgetActionAck { done, skipped, failed }

/// 主 isolate 收到的桌面动作处理器。
typedef HomeWidgetActionHandler = Future<HomeWidgetActionAck> Function(Uri uri);

/// 把 `home_widget` 后台引擎里的桌面动作转发给仍然活着的主 isolate。
///
/// Android 上 `home_widget` 用 JobIntentService 在**同一进程**另起一个
/// FlutterEngine 执行回调，因此可以用 [IsolateNameServer] 定位主 isolate 的端口。
/// 主 isolate 的 Provider 才是唯一可信的数据源：后台 isolate 自建 Provider
/// 读到的是陈旧副本，写盘会整表覆盖主 isolate 的改动。
class HomeWidgetActionBridge {
  HomeWidgetActionBridge._();

  /// 端口名，主 isolate 注册、后台 isolate 查找，两端必须一致。
  static const String portName = 'duoyi.home_widget.action';

  /// 后台 isolate 等待主 isolate 完成动作与 payload 刷新的上限。
  static const Duration ackTimeout = Duration(seconds: 10);

  static ReceivePort? _mainPort;
  static HomeWidgetActionHandler? _handler;
  static Future<void> _serial = Future<void>.value();

  /// 测试用：替换名称服务查找（默认走 [IsolateNameServer]）。
  @visibleForTesting
  static SendPort? Function(String name) debugLookupPort = (String name) =>
      IsolateNameServer.lookupPortByName(name);

  /// 主 isolate 是否已经注册处理器；用于断言热重启/重复初始化不会叠加。
  @visibleForTesting
  static bool get hasMainHandler => _mainPort != null;

  /// 主 isolate 注册唯一的动作处理器；重复调用直接复用已有端口。
  static void registerMainHandler(HomeWidgetActionHandler handler) {
    if (_mainPort != null) return;
    _handler = handler;
    final port = ReceivePort('$portName.main');
    _mainPort = port;
    try {
      // 热重启后旧映射指向已经销毁的 isolate，先清掉再登记，否则
      // `registerPortWithName` 会保留旧映射并返回 false。
      IsolateNameServer.removePortNameMapping(portName);
      IsolateNameServer.registerPortWithName(port.sendPort, portName);
    } catch (error, stackTrace) {
      debugPrint(
        '[HomeWidget] action bridge register failed: $error\n$stackTrace',
      );
    }
    port.listen(_dispatch);
  }

  /// 注销端口映射并丢弃处理器（进程退出/测试清理用）。
  static void unregisterMainHandler() {
    final port = _mainPort;
    _mainPort = null;
    _handler = null;
    try {
      IsolateNameServer.removePortNameMapping(portName);
    } catch (error, stackTrace) {
      debugPrint(
        '[HomeWidget] action bridge unregister failed: $error\n$stackTrace',
      );
    }
    port?.close();
  }

  /// 把动作转发给主 isolate 并等待 ACK。
  ///
  /// 返回值表示“主 isolate 是否接管了这条动作”，而不是动作是否成功：
  /// 端口存在时，即使主 isolate 执行失败或 ACK 超时也必须返回 true，
  /// 调用方不得再在后台 isolate 本地重跑，否则会重复写盘/重复打卡。
  static Future<bool> forwardToMainIsolate(
    Uri uri, {
    Duration timeout = ackTimeout,
  }) async {
    SendPort? mainPort;
    try {
      mainPort = debugLookupPort(portName);
    } catch (error, stackTrace) {
      debugPrint(
        '[HomeWidget] action bridge lookup failed: $error\n$stackTrace',
      );
      mainPort = null;
    }
    if (mainPort == null) return false;
    final reply = ReceivePort('$portName.reply');
    try {
      // 只传 URI 字符串与回信端口：两者都能跨 isolate 传递，且不携带重对象。
      mainPort.send(<Object>[uri.toString(), reply.sendPort]);
      final ack = await reply.first.timeout(timeout, onTimeout: () => null);
      if (ack == null) {
        debugPrint('[HomeWidget] action bridge ack timeout');
      } else {
        debugPrint('[HomeWidget] action bridge ack=$ack');
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[HomeWidget] action bridge forward failed: $error\n$stackTrace',
      );
    } finally {
      reply.close();
    }
    return true;
  }

  static void _dispatch(Object? message) {
    if (message is! List || message.length != 2) return;
    final uri = _parseUri(message[0]);
    final replyTo = message[1];
    if (uri == null || replyTo is! SendPort) return;
    // 小组件动作串行处理：连点两下时不会并发双写，ACK 也按顺序返回。
    _serial = _serial.then((_) => _runAndReply(uri, replyTo));
  }

  static Future<void> _runAndReply(Uri uri, SendPort replyTo) async {
    var ack = HomeWidgetActionAck.failed;
    try {
      final handler = _handler;
      if (handler == null) {
        ack = HomeWidgetActionAck.skipped;
      } else {
        ack = await handler(uri);
      }
    } catch (error, stackTrace) {
      // URI 可能带用户输入文本，日志只记录异常本身。
      debugPrint(
        '[HomeWidget] action bridge handler failed: $error\n$stackTrace',
      );
    } finally {
      try {
        replyTo.send(ack.name);
      } catch (_) {
        // 主 isolate 已退出：后台侧按“已接管”处理，不再本地重跑。
      }
    }
  }

  static Uri? _parseUri(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return Uri.tryParse(value);
  }
}
