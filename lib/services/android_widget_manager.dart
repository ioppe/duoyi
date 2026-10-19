import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/platform_info.dart';

enum DuoyiWidgetKind {
  todo,
  focus,
  habit,
  calendar,
  schedule,
  goal,
  course,
  note,
  anniversary,
}

enum AndroidWidgetStyle {
  compact,
  standard,
  detailed;

  static AndroidWidgetStyle fromId(String? id) {
    return AndroidWidgetStyle.values.firstWhere(
      (style) => style.id == id,
      orElse: () => AndroidWidgetStyle.standard,
    );
  }

  String get id {
    return switch (this) {
      AndroidWidgetStyle.compact => 'compact',
      AndroidWidgetStyle.standard => 'standard',
      AndroidWidgetStyle.detailed => 'detailed',
    };
  }
}

enum AndroidWidgetPinResult {
  requested,
  unsupported,
  unsupportedPlatform,
  unsupportedLauncher,
  permissionDenied,
  confirmationBlocked,
  invalidKind,
  unavailable;

  static AndroidWidgetPinResult fromId(String? id) {
    return switch (id) {
      'requested' => AndroidWidgetPinResult.requested,
      'unsupported' => AndroidWidgetPinResult.unsupported,
      'unsupported_platform' => AndroidWidgetPinResult.unsupportedPlatform,
      'unsupported_launcher' => AndroidWidgetPinResult.unsupportedLauncher,
      'permission_denied' => AndroidWidgetPinResult.permissionDenied,
      'confirmation_blocked' => AndroidWidgetPinResult.confirmationBlocked,
      'invalid_kind' => AndroidWidgetPinResult.invalidKind,
      _ => AndroidWidgetPinResult.unavailable,
    };
  }
}

enum AndroidWidgetPinFinalStatus {
  success,
  invalidWidgetId,
  timeout,
  unavailable,
}

class AndroidWidgetPinRequest {
  final AndroidWidgetPinResult result;
  final String? requestId;

  const AndroidWidgetPinRequest({required this.result, this.requestId});

  bool get isRequested => result == AndroidWidgetPinResult.requested;

  static AndroidWidgetPinRequest fromNativeStatus(String? status) {
    final raw = status ?? '';
    if (raw.startsWith('requested:')) {
      final requestId = raw.substring('requested:'.length).trim();
      return AndroidWidgetPinRequest(
        result: AndroidWidgetPinResult.requested,
        requestId: requestId.isEmpty ? null : requestId,
      );
    }
    return AndroidWidgetPinRequest(
      result: AndroidWidgetPinResult.fromId(status),
    );
  }
}

class AndroidWidgetPinConfirmation {
  final AndroidWidgetPinFinalStatus status;
  final String requestId;
  final String kind;
  final AndroidWidgetStyle style;
  final int widgetId;
  final DateTime? confirmedAt;

  const AndroidWidgetPinConfirmation({
    required this.status,
    required this.requestId,
    this.kind = '',
    this.style = AndroidWidgetStyle.standard,
    this.widgetId = -1,
    this.confirmedAt,
  });

  bool get isSuccess => status == AndroidWidgetPinFinalStatus.success;

  static AndroidWidgetPinConfirmation? fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) return null;
    final requestId = raw['requestId']?.toString() ?? '';
    if (requestId.isEmpty) return null;
    final confirmedAtMillis = raw['confirmedAt'];
    final millis = confirmedAtMillis is int
        ? confirmedAtMillis
        : int.tryParse(confirmedAtMillis?.toString() ?? '');
    final nativeStatus = raw['status']?.toString();
    return AndroidWidgetPinConfirmation(
      status: switch (nativeStatus) {
        'confirmed' => AndroidWidgetPinFinalStatus.success,
        'confirmed_unverified' => AndroidWidgetPinFinalStatus.success,
        'invalid_widget_id' => AndroidWidgetPinFinalStatus.invalidWidgetId,
        _ => AndroidWidgetPinFinalStatus.unavailable,
      },
      requestId: requestId,
      kind: raw['kind']?.toString() ?? '',
      style: AndroidWidgetStyle.fromId(raw['style']?.toString()),
      widgetId: raw['widgetId'] is int
          ? raw['widgetId'] as int
          : int.tryParse(raw['widgetId']?.toString() ?? '') ?? -1,
      confirmedAt: millis == null || millis <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }
}

class AndroidWidgetManager {
  AndroidWidgetManager._();

  static const MethodChannel _channel = MethodChannel('duoyi/widgets');

  static Future<bool> canRequestPinWidget() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canRequestPinWidget') ?? false;
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] canRequestPinWidget failed: $e\n$st');
      return false;
    }
  }

  static Future<AndroidWidgetPinResult> checkPinSupport() async {
    if (!_isAndroid) {
      return AndroidWidgetPinResult.unsupportedPlatform;
    }
    try {
      final supported =
          await _channel.invokeMethod<bool>('canRequestPinWidget') ?? false;
      return supported
          ? AndroidWidgetPinResult.requested
          : AndroidWidgetPinResult.unsupportedLauncher;
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] checkPinSupport failed: $e\n$st');
      return AndroidWidgetPinResult.unavailable;
    }
  }

  static Future<bool> openWidgetSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openWidgetSettings') ?? false;
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] openWidgetSettings failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> canOpenWidgetSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canOpenWidgetSettings') ??
          false;
    } catch (e, st) {
      debugPrint(
        '[AndroidWidgetManager] canOpenWidgetSettings failed: $e\n$st',
      );
      return false;
    }
  }

  static Future<AndroidWidgetPinResult> requestPinWidget(
    DuoyiWidgetKind kind, {
    AndroidWidgetStyle style = AndroidWidgetStyle.standard,
  }) async {
    final request = await requestPinWidgetDetailed(kind, style: style);
    return request.result;
  }

  static Future<AndroidWidgetPinRequest> requestPinWidgetDetailed(
    DuoyiWidgetKind kind, {
    AndroidWidgetStyle style = AndroidWidgetStyle.standard,
  }) async {
    if (!_isAndroid) {
      return const AndroidWidgetPinRequest(
        result: AndroidWidgetPinResult.unsupportedPlatform,
      );
    }
    try {
      final status = await _channel.invokeMethod<String>(
        'requestPinWidget',
        <String, Object?>{'kind': kind.id, 'style': style.id},
      );
      return AndroidWidgetPinRequest.fromNativeStatus(status);
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] requestPinWidget failed: $e\n$st');
      return const AndroidWidgetPinRequest(
        result: AndroidWidgetPinResult.unavailable,
      );
    }
  }

  static Future<AndroidWidgetPinConfirmation?> lastPinResult(
    String requestId,
  ) async {
    if (!_isAndroid || requestId.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'lastPinResult',
        <String, Object?>{'requestId': requestId},
      );
      if (raw is! Map) return null;
      return AndroidWidgetPinConfirmation.fromMap(raw);
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] lastPinResult failed: $e\n$st');
      return null;
    }
  }

  static Future<void> clearPinResult(String requestId) async {
    if (!_isAndroid || requestId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('clearPinResult', <String, Object?>{
        'requestId': requestId,
      });
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] clearPinResult failed: $e\n$st');
    }
  }

  static Future<void> cancelPinRequest(String requestId) async {
    if (!_isAndroid || requestId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('cancelPinRequest', <String, Object?>{
        'requestId': requestId,
      });
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] cancelPinRequest failed: $e\n$st');
    }
  }

  static Future<int?> applyDisplayModeToExistingWidgets(
    AndroidWidgetStyle style,
  ) async {
    if (!_isAndroid) return 0;
    try {
      return await _channel.invokeMethod<int>(
            'applyWidgetDisplayMode',
            <String, Object?>{'style': style.id},
          ) ??
          0;
    } catch (e, st) {
      debugPrint(
        '[AndroidWidgetManager] applyWidgetDisplayMode failed: $e\n$st',
      );
      return null;
    }
  }

  static Future<int?> refreshAllWidgets() async {
    if (!_isAndroid) return 0;
    try {
      return await _channel.invokeMethod<int>('refreshAllWidgets') ?? 0;
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] refreshAllWidgets failed: $e\n$st');
      return null;
    }
  }

  static Future<AndroidWidgetPinConfirmation> waitForPinResult(
    String requestId, {
    Duration timeout = const Duration(minutes: 2),
    Duration pollInterval = const Duration(milliseconds: 700),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final result = await lastPinResult(requestId);
      if (result != null) return result;
      await Future<void>.delayed(pollInterval);
    }
    debugPrint(
      '[AndroidWidgetManager] pin result timed out; keep pending request '
      'alive for late launcher callback requestId=$requestId',
    );
    return AndroidWidgetPinConfirmation(
      status: AndroidWidgetPinFinalStatus.timeout,
      requestId: requestId,
    );
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    return PlatformInfo.isAndroid;
  }
}

extension DuoyiWidgetKindId on DuoyiWidgetKind {
  String get id {
    return switch (this) {
      DuoyiWidgetKind.todo => 'todo',
      DuoyiWidgetKind.focus => 'focus',
      DuoyiWidgetKind.habit => 'habit',
      DuoyiWidgetKind.calendar => 'calendar',
      DuoyiWidgetKind.schedule => 'schedule',
      DuoyiWidgetKind.goal => 'goal',
      DuoyiWidgetKind.course => 'course',
      DuoyiWidgetKind.note => 'note',
      DuoyiWidgetKind.anniversary => 'anniversary',
    };
  }
}
