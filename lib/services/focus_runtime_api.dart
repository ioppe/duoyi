/// 同账号多端专注的 HTTP / WebSocket 客户端。
///
/// 协议见 `docs/focus-runtime-sync.md`：
/// - `GET /api/focus/runtime`
/// - `POST /api/focus/runtime/commands`
/// - `WS /ws/focus/runtime/events`（事件名 `focus.runtime`）
///
/// 这里只做传输与解析，不缓存权威状态、不重放命令；权威状态归
/// `FocusSyncCoordinator` / `PomodoroProvider` 投影。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/focus_runtime.dart';
import 'api_client.dart';

/// 能力开关：`/api/config` 的 `features.focus_runtime_sync`。
const String focusRuntimeFeatureKey = 'focus_runtime_sync';

/// 明确能力开关状态：未知（配置未加载/网络失败）不等于关闭。
enum FocusRuntimeFeatureState { enabled, disabled, unknown }

FocusRuntimeFeatureState focusRuntimeFeatureState(
  Map<String, dynamic> serverConfig,
) {
  final features = serverConfig['features'];
  if (features is! Map) return FocusRuntimeFeatureState.unknown;
  final value = features[focusRuntimeFeatureKey];
  if (value == true) return FocusRuntimeFeatureState.enabled;
  if (value == false) return FocusRuntimeFeatureState.disabled;
  return FocusRuntimeFeatureState.unknown;
}

/// HTTP 404/405 表示后端明确没有本路由（旧后端）——只有这种情况可以回退本地。
bool isFocusRuntimeRouteMissing(Object error) {
  final message = error is ApiException ? error.message : error.toString();
  return RegExp(r'^\s*40[45]:').hasMatch(message) || message.contains('接口不存在');
}

/// WebSocket 抽象：便于测试注入，且由调用方决定何时释放。
abstract class FocusRuntimeSocket {
  Stream<Object?> get messages;
  void send(Object? data);
  Future<void> close([int? code, String? reason]);
}

typedef FocusRuntimeSocketFactory = FocusRuntimeSocket Function(Uri uri);

class WebSocketFocusRuntimeSocket implements FocusRuntimeSocket {
  WebSocketFocusRuntimeSocket(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<Object?> get messages => _channel.stream;

  @override
  void send(Object? data) => _channel.sink.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    try {
      await _channel.sink.close(code, reason);
    } catch (_) {
      // 关闭失败可容忍：连接已经断开，句柄随 Stream 一起释放。
    }
  }
}

FocusRuntimeSocket defaultFocusRuntimeSocketFactory(Uri uri) =>
    WebSocketFocusRuntimeSocket(WebSocketChannel.connect(uri));

class FocusRuntimeApi {
  static const String runtimePath = '/api/focus/runtime';
  static const String commandsPath = '/api/focus/runtime/commands';
  static const String eventsPath = '/ws/focus/runtime/events';

  final ApiClient client;
  final FocusRuntimeSocketFactory socketFactory;
  final String? _tokenOverride;
  final String _baseUrl;

  FocusRuntimeApi(
    this.client, {
    FocusRuntimeSocketFactory? socketFactory,
    String? tokenOverride,
  }) : socketFactory = socketFactory ?? defaultFocusRuntimeSocketFactory,
       _tokenOverride = tokenOverride ?? client.token,
       _baseUrl = client.baseUrl;

  bool get canUse => token != null && token!.isNotEmpty;

  /// 捕获到的凭证：用于让旧代际的请求在换号后自动失效。
  String? get token {
    final captured = _tokenOverride?.trim();
    return captured == null || captured.isEmpty ? null : captured;
  }

  String get baseUrl => _baseUrl;

  void _ensureCanUse() {
    if (!canUse) throw const ApiException('请先登录后再同步专注状态');
    if (client.token?.trim() != token || client.baseUrl != baseUrl) {
      throw const ApiException('专注连接身份已变化');
    }
  }

  Future<FocusRuntimeSnapshot> fetchRuntime() async {
    _ensureCanUse();
    final response = await client.get(runtimePath);
    return _parseSnapshotPayload(response);
  }

  Future<FocusRuntimeSnapshot> sendCommand(FocusRuntimeCommand command) async {
    _ensureCanUse();
    final response = await client.post(commandsPath, command.toJson());
    return _parseSnapshotPayload(response);
  }

  /// 命令成功可能返回裸快照，也可能包一层 `snapshot`；两种都接受。
  static FocusRuntimeSnapshot _parseSnapshotPayload(Map<String, dynamic> json) {
    final nested = json['snapshot'];
    if (nested is Map) {
      final parsed = FocusRuntimeSnapshot.tryParse(nested);
      if (parsed != null) return parsed;
    }
    final parsed = FocusRuntimeSnapshot.tryParse(json);
    if (parsed != null) return parsed;
    throw const ApiException('专注状态返回结构错误：缺少 runtime 快照');
  }

  /// 解析一条 WS 文本消息；`ping`/心跳/其他事件返回 null。
  static FocusRuntimeSnapshot? parseEventMessage(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = json.decode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final event = decoded['event']?.toString();
    if (event != null && event != 'focus.runtime') return null;
    final data = decoded['data'];
    if (data == null) return null;
    return FocusRuntimeSnapshot.tryParse(data);
  }

  /// 连接用的 WS URI；无法构造（未登录/地址非法）返回 null。
  Uri? eventsUri() =>
      buildRuntimeWebSocketUri(baseUrl: baseUrl, token: token ?? '');

  /// 同源 + 部署路径前缀：`https://host/duoyi` → `wss://host/duoyi/ws/...`。
  static Uri? buildRuntimeWebSocketUri({
    required String baseUrl,
    required String token,
    String path = eventsPath,
  }) {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return null;
    final base = _baseUri(baseUrl);
    if (base == null) return null;
    final scheme = switch (base.scheme.toLowerCase()) {
      'https' || 'wss' => 'wss',
      'http' || 'ws' => 'ws',
      _ => null,
    };
    final host = base.host.trim();
    if (scheme == null || host.isEmpty) return null;
    if (base.hasPort && base.port == 0) return null;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final prefix = _deploymentPrefix(base.path);
    return Uri(
      scheme: scheme,
      host: host,
      port: base.hasPort ? base.port : null,
      path: '$prefix$normalizedPath',
      queryParameters: <String, String>{'token': cleanToken},
    );
  }

  /// 部署路径前缀：去掉尾部 `/`；已带 `/api` 时剥掉（HTTP 侧同样如此）。
  static String _deploymentPrefix(String rawPath) {
    var prefix = rawPath.trim();
    if (prefix.isEmpty || prefix == '/') return '';
    prefix = prefix.replaceAll(RegExp(r'/+$'), '');
    if (prefix.toLowerCase().endsWith('/api')) {
      prefix = prefix.substring(0, prefix.length - 4);
    }
    if (prefix.isEmpty || prefix == '/') return '';
    if (!prefix.startsWith('/')) prefix = '/$prefix';
    return prefix;
  }

  static Uri? _baseUri(String baseUrl) {
    final clean = baseUrl.trim();
    if (clean.isEmpty) return Uri.base;
    try {
      return Uri.tryParse(clean);
    } catch (_) {
      return null;
    }
  }

  /// 诊断日志脱敏：不得把 token 原样写进日志。
  static String sanitizeDiagnostic(Object? diagnostic, {String? token}) {
    var text = diagnostic?.toString() ?? '';
    final cleanToken = token?.trim();
    if (cleanToken != null && cleanToken.isNotEmpty) {
      text = text.replaceAll(cleanToken, '<redacted-token>');
    }
    text = text.replaceAllMapped(
      RegExp(r'([?&](?:access_)?token=)[^&#\s)]+', caseSensitive: false),
      (match) => '${match.group(1)}<redacted-token>',
    );
    return text.replaceAllMapped(
      RegExp(r'(Bearer\s+)[^\s,;]+', caseSensitive: false),
      (match) => '${match.group(1)}<redacted-token>',
    );
  }

  static void debugRealtimeError(String label, Object error, {String? token}) {
    if (!kDebugMode) return;
    debugPrint(
      '[FocusRuntimeApi] $label: '
      '${sanitizeDiagnostic(error, token: token)}',
    );
  }
}
