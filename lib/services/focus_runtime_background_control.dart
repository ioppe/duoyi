import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/feature_flags.dart';
import '../core/server_connection.dart';
import '../models/focus_runtime.dart';
import '../models/pomodoro.dart';
import '../providers/auth_provider.dart';
import '../providers/pomodoro_provider.dart';
import 'api_client.dart';
import 'focus_runtime_api.dart';
import 'home_widget_action.dart';

/// A cold widget action has no root coordinator. It submits one bound command
/// over HTTP and returns a projection; it never owns a timer or a socket.
class FocusRuntimeBackgroundResult {
  const FocusRuntimeBackgroundResult({
    required this.handled,
    this.changed = false,
    this.snapshot,
  });

  final bool handled;
  final bool changed;
  final FocusRuntimeSnapshot? snapshot;
}

class FocusRuntimeBackgroundControl {
  static const _local = FocusRuntimeBackgroundResult(handled: false);
  static const _blocked = FocusRuntimeBackgroundResult(handled: true);
  static const deviceIdKey = 'duoyi_focus_sync_device_id';

  static Future<FocusRuntimeBackgroundResult> run(
    HomeWidgetActionRequest request,
    SharedPreferences prefs, {
    ApiClient? client,
  }) async {
    if (!request.isFocusControl || !FeatureFlags.cloudSyncV2) return _local;
    if (prefs.getBool(PomodoroProvider.focusRemoteMarkerKey) != true) {
      return _local;
    }
    final scope = HomeWidgetAccountScope.fromPreferences(prefs);
    if (scope.blockReason != HomeWidgetActionBlockReason.none ||
        !request.isBoundFocusControl ||
        request.focusScope != scope.focusControlScope) {
      return _blocked;
    }
    String baseUrl;
    try {
      baseUrl = ServerConnection.normalize(
        prefs.getString(AuthProvider.serverUrlStorageKey) ??
            ServerConnection.defaultBaseUrl(),
      );
      if (scope.sessionServer != ServerConnection.identity(baseUrl)) {
        return _blocked;
      }
    } on FormatException {
      return _blocked;
    }
    final ownedHttp = client == null ? http.Client() : null;
    final api = FocusRuntimeApi(
      client ??
          ApiClient(
            baseUrl: baseUrl,
            token: scope.token,
            httpClient: ownedHttp,
          ),
    );
    Future<bool> isCurrent() async {
      await prefs.reload();
      try {
        final currentServer = ServerConnection.normalize(
          prefs.getString(AuthProvider.serverUrlStorageKey) ??
              ServerConnection.defaultBaseUrl(),
        );
        if (currentServer != baseUrl) return false;
      } on FormatException {
        return false;
      }
      final current = HomeWidgetAccountScope.fromPreferences(prefs);
      return current.blockReason == HomeWidgetActionBlockReason.none &&
          current.owner == scope.owner &&
          current.token == scope.token &&
          current.sessionServer == scope.sessionServer &&
          current.focusControlScope == request.focusScope;
    }

    try {
      final snapshot = await api.fetchRuntime();
      if (!await isCurrent()) return _blocked;
      final runtime = snapshot.runtime;
      if (request.focusSessionId != runtime.sessionId ||
          request.focusRevision != runtime.revision ||
          request.focusState?.wireName != runtime.status.wireName) {
        return FocusRuntimeBackgroundResult(handled: true, snapshot: snapshot);
      }
      final action = switch (request.kind) {
        HomeWidgetActionKind.startPomodoro =>
          runtime.status.isPaused
              ? FocusRuntimeAction.resume
              : FocusRuntimeAction.start,
        HomeWidgetActionKind.pausePomodoro => FocusRuntimeAction.pause,
        HomeWidgetActionKind.stopPomodoro => FocusRuntimeAction.stop,
        _ => null,
      };
      if (action == null) return _blocked;
      Map<String, dynamic>? payload;
      if (action == FocusRuntimeAction.start) {
        final raw = prefs.getString('pomodoro_config');
        final config = raw == null
            ? PomodoroConfig()
            : PomodoroConfig.fromJson(jsonDecode(raw));
        payload = FocusRuntimeCommand.startPayload(
          mode: runtime.mode,
          config: config.toJson(),
          taskName: runtime.taskName,
          todoId: runtime.todoId,
          subtaskId: runtime.subtaskId,
          todoTitle: runtime.todoTitle,
          tag: runtime.tag,
          focusRoomId: runtime.focusRoomId,
        );
      }
      var deviceId = prefs.getString(deviceIdKey)?.trim();
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = newFocusCommandId();
        await prefs.setString(deviceIdKey, deviceId);
      }
      if (!await isCurrent()) return _blocked;
      final next = await api.sendCommand(
        FocusRuntimeCommand.create(
          deviceId: deviceId,
          sessionId: runtime.sessionId,
          expectedRevision: runtime.revision,
          action: action,
          payload: payload,
        ),
      );
      if (!await isCurrent()) return _blocked;
      return FocusRuntimeBackgroundResult(
        handled: true,
        changed: true,
        snapshot: next,
      );
    } catch (error) {
      if (!await isCurrent()) return _blocked;
      if (isFocusRuntimeRouteMissing(error)) {
        await prefs.remove(PomodoroProvider.focusRemoteMarkerKey);
        return _local;
      }
      // Failure never starts a second local session or replays an old command.
      return _blocked;
    } finally {
      ownedHttp?.close();
    }
  }
}
