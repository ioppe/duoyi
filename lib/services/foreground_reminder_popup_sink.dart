import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_clock.dart';
import 'reminder_sinks.dart';

typedef ReminderPopupContextGetter = BuildContext? Function();
typedef ReminderPopupPayloadOpener = void Function(String payload);
typedef ReminderPopupForegroundGetter = bool Function();

class ForegroundReminderPopupSink implements ReminderPopupSink {
  static const Duration _visiblePopupDuplicateWindow = Duration(seconds: 3);

  final ReminderPopupContextGetter contextGetter;
  final ReminderPopupPayloadOpener? onOpenPayload;
  final ReminderNotificationSink? notificationFallback;
  final ReminderPopupForegroundGetter isForegroundGetter;
  final DateTime Function() nowGetter;
  final Map<int, Timer> _timers = {};
  final Map<int, int> _generations = <int, int>{};
  final Map<int, Future<void>> _fallbackOperations = <int, Future<void>>{};
  final Map<int, Future<void>> _dialogOperations = <int, Future<void>>{};
  final Set<int> _visibleDialogIds = <int>{};
  final Map<String, DateTime> _recentVisibleDialogSignatures =
      <String, DateTime>{};
  final Map<int, String> _visibleDialogSignatures = <int, String>{};
  final Map<int, int> _visibleDialogGenerations = <int, int>{};
  final Map<int, NavigatorState> _visibleNavigators = <int, NavigatorState>{};

  ForegroundReminderPopupSink({
    required this.contextGetter,
    this.onOpenPayload,
    this.notificationFallback,
    ReminderPopupForegroundGetter? isForegroundGetter,
    DateTime Function()? nowGetter,
  }) : isForegroundGetter = isForegroundGetter ?? _defaultIsForeground,
       nowGetter = nowGetter ?? AppClock.now;

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    final generation = _invalidate(id);
    await _closeVisibleDialog(id, generation);
    if (!_isCurrent(id, generation)) return;
    final delay = when.difference(nowGetter());
    if (delay <= Duration.zero) {
      throw StateError('提醒时间已过去，popup 提醒未注册');
    }
    try {
      await _replaceFallback(id, generation, () async {
        await _scheduleFallbackOnce(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
        );
      });
    } catch (error, stackTrace) {
      _reportFallbackIssue(id, payload, error, stackTrace);
      rethrow;
    }
    if (!_isCurrent(id, generation)) return;
    final hasFallback = notificationFallback != null;
    _timers[id] = Timer(delay, () {
      unawaited(
        _prepareForegroundDelivery(
          id: id,
          generation: generation,
          title: title,
          body: body,
          payload: payload,
          cancelFallbackAfterDialog: hasFallback,
        ).catchError((Object error, StackTrace stackTrace) {
          _reportFallbackIssue(id, payload, error, stackTrace);
        }),
      );
    });
  }

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    final generation = _invalidate(id);
    await _closeVisibleDialog(id, generation);
    if (!_isCurrent(id, generation)) return;
    try {
      await _replaceFallback(id, generation, () async {
        await _scheduleFallbackRepeating(
          id: id,
          title: title,
          body: body,
          hour: hour,
          minute: minute,
          weekdays: weekdays,
          payload: payload,
        );
      });
    } catch (error, stackTrace) {
      _reportFallbackIssue(id, payload, error, stackTrace);
      rethrow;
    }
    _scheduleRepeatingTimer(
      id: id,
      generation: generation,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: payload,
    );
  }

  void _scheduleRepeatingTimer({
    required int id,
    required int generation,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required List<int>? weekdays,
    required String? payload,
  }) {
    if (!_isCurrent(id, generation)) return;
    final next = _nextOccurrence(hour, minute, weekdays, nowGetter());
    final delay = next.difference(nowGetter());
    _timers[id] = Timer(delay, () {
      unawaited(
        _prepareForegroundDelivery(
          id: id,
          generation: generation,
          title: title,
          body: body,
          payload: payload,
          cancelFallbackAfterDialog: true,
          repeating: true,
          onForegroundDelivered: () async {
            await _refreshRepeatingFallback(
              id: id,
              generation: generation,
              title: title,
              body: body,
              hour: hour,
              minute: minute,
              weekdays: weekdays,
              payload: payload,
            );
            _scheduleRepeatingTimer(
              id: id,
              generation: generation,
              title: title,
              body: body,
              hour: hour,
              minute: minute,
              weekdays: weekdays,
              payload: payload,
            );
          },
          onBackgroundDelivered: () async {
            _scheduleRepeatingTimer(
              id: id,
              generation: generation,
              title: title,
              body: body,
              hour: hour,
              minute: minute,
              weekdays: weekdays,
              payload: payload,
            );
          },
        ).catchError((Object error, StackTrace stackTrace) {
          _reportFallbackIssue(id, payload, error, stackTrace);
        }),
      );
    });
  }

  Future<void> _scheduleFallbackOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    final fallback = notificationFallback;
    if (fallback == null) return;
    final fallbackPayload = _fallbackPayload(payload);
    final resultSink = fallback is ReminderNotificationScheduleResultSink
        ? fallback as ReminderNotificationScheduleResultSink
        : null;
    if (resultSink != null) {
      final scheduled = await resultSink.scheduleOnceWithResult(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: fallbackPayload,
      );
      if (!scheduled) throw StateError('系统通知兜底注册失败');
      return;
    }
    await fallback.scheduleOnce(
      id: id,
      title: title,
      body: body,
      when: when,
      payload: fallbackPayload,
    );
  }

  Future<void> _scheduleFallbackRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    final fallback = notificationFallback;
    if (fallback == null) return;
    final fallbackPayload = _fallbackPayload(payload);
    final resultSink = fallback is ReminderNotificationScheduleResultSink
        ? fallback as ReminderNotificationScheduleResultSink
        : null;
    if (resultSink != null) {
      final scheduled = await resultSink.scheduleDailyWithResult(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        payload: fallbackPayload,
      );
      if (!scheduled) throw StateError('系统重复通知兜底注册失败');
      return;
    }
    await fallback.scheduleDaily(
      id: id,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: fallbackPayload,
    );
  }

  Future<void> _refreshRepeatingFallback({
    required int id,
    required int generation,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required List<int>? weekdays,
    required String? payload,
  }) async {
    if (notificationFallback == null || !_isCurrent(id, generation)) return;
    try {
      await _replaceFallback(id, generation, () async {
        await _scheduleFallbackRepeating(
          id: id,
          title: title,
          body: body,
          hour: hour,
          minute: minute,
          weekdays: weekdays,
          payload: payload,
        );
      });
    } catch (error, stackTrace) {
      _reportFallbackIssue(id, payload, error, stackTrace);
    }
  }

  Future<void> _replaceFallback(
    int id,
    int generation,
    Future<void> Function() schedule,
  ) {
    return _serializeFallbackOperation(id, () async {
      if (!_isCurrent(id, generation)) return;
      await notificationFallback?.cancel(id);
      if (!_isCurrent(id, generation)) return;
      await schedule();
    });
  }

  Future<void> _serializeFallbackOperation(
    int id,
    Future<void> Function() operation,
  ) async {
    final previous = _fallbackOperations[id] ?? Future<void>.value();
    final current = previous.catchError((Object _) {}).then((_) => operation());
    _fallbackOperations[id] = current;
    try {
      await current;
    } finally {
      if (identical(_fallbackOperations[id], current)) {
        _fallbackOperations.remove(id);
      }
    }
  }

  Future<void> _prepareForegroundDelivery({
    required int id,
    required int generation,
    required String title,
    required String body,
    required String? payload,
    required bool cancelFallbackAfterDialog,
    bool repeating = false,
    Future<void> Function()? onForegroundDelivered,
    Future<void> Function()? onBackgroundDelivered,
  }) async {
    if (!_isCurrent(id, generation)) return;
    _timers.remove(id);
    if (!isForegroundGetter()) {
      if (repeating) {
        await (onBackgroundDelivered ?? onForegroundDelivered)?.call();
      }
      return;
    }
    final context = contextGetter();
    if (context == null || !context.mounted) {
      if (repeating) {
        await (onBackgroundDelivered ?? onForegroundDelivered)?.call();
      }
      return;
    }
    await _showOrFallback(
      id: id,
      generation: generation,
      title: title,
      body: body,
      payload: payload,
      cancelFallbackAfterDialog: cancelFallbackAfterDialog,
      repeating: repeating,
      onForegroundDelivered: onForegroundDelivered,
      onBackgroundDelivered: onBackgroundDelivered,
    );
  }

  Future<void> _showOrFallback({
    required int id,
    required int generation,
    required String title,
    required String body,
    required String? payload,
    required bool cancelFallbackAfterDialog,
    bool repeating = false,
    Future<void> Function()? onForegroundDelivered,
    Future<void> Function()? onBackgroundDelivered,
  }) async {
    if (!_isCurrent(id, generation)) return;
    var shown = false;
    await _serializeDialogOperation(id, generation, () async {
      shown = isForegroundGetter()
          ? _show(id: id, title: title, body: body, payload: payload)
          : false;
    });
    if (!_isCurrent(id, generation)) return;
    if (!shown) {
      if (repeating) {
        await (onBackgroundDelivered ?? onForegroundDelivered)?.call();
      }
      return;
    }
    if (cancelFallbackAfterDialog && !repeating) {
      try {
        await _serializeFallbackOperation(id, () async {
          if (_isCurrent(id, generation)) {
            await notificationFallback?.cancel(id);
          }
        });
      } catch (error, stackTrace) {
        _reportFallbackIssue(id, payload, error, stackTrace);
      }
    }
    if (_isCurrent(id, generation)) await onForegroundDelivered?.call();
  }

  String? _fallbackPayload(String? payload) {
    if (payload == null || payload.isEmpty) return payload;
    final uri = Uri.tryParse(payload);
    if (uri == null) return payload;
    final query = Map<String, String>.from(uri.queryParameters)
      ..putIfAbsent('fallback', () => 'popup_notification');
    return uri.replace(queryParameters: query).toString();
  }

  @override
  Future<void> cancel(int id) async {
    final generation = _invalidate(id);
    Object? cancelError;
    StackTrace? cancelStackTrace;
    try {
      await _closeVisibleDialog(id, generation);
    } catch (error, stackTrace) {
      cancelError = error;
      cancelStackTrace = stackTrace;
    }
    try {
      await _serializeFallbackOperation(id, () async {
        if (_isCurrent(id, generation)) {
          await notificationFallback?.cancel(id);
        }
      });
    } catch (error, stackTrace) {
      cancelError ??= error;
      cancelStackTrace ??= stackTrace;
    } finally {
      if (_isCurrent(id, generation)) _clearVisibleDialogState(id);
    }
    if (cancelError != null) {
      Error.throwWithStackTrace(cancelError, cancelStackTrace!);
    }
  }

  int _invalidate(int id) {
    final generation = (_generations[id] ?? 0) + 1;
    _generations[id] = generation;
    _timers.remove(id)?.cancel();
    return generation;
  }

  bool _isCurrent(int id, int generation) => _generations[id] == generation;

  Future<void> _closeVisibleDialog(int id, int generation) {
    return _serializeDialogOperation(id, generation, () async {
      final navigator = _visibleNavigators[id];
      if (navigator != null && navigator.mounted) {
        await navigator.maybePop();
      }
      if (_isCurrent(id, generation)) {
        _clearVisibleDialogState(id, generation: generation);
      }
    });
  }

  Future<void> _serializeDialogOperation(
    int id,
    int generation,
    Future<void> Function() operation,
  ) async {
    final previous = _dialogOperations[id] ?? Future<void>.value();
    final current = previous.catchError((Object _) {}).then((_) async {
      if (_isCurrent(id, generation)) await operation();
    });
    _dialogOperations[id] = current;
    try {
      await current;
    } finally {
      if (identical(_dialogOperations[id], current)) {
        _dialogOperations.remove(id);
      }
    }
  }

  void _clearVisibleDialogState(
    int id, {
    String? expectedSignature,
    int? generation,
  }) {
    if (expectedSignature != null &&
        _visibleDialogSignatures[id] != expectedSignature) {
      return;
    }
    if (generation != null && _visibleDialogGenerations[id] != generation) {
      return;
    }
    _visibleNavigators.remove(id);
    _visibleDialogSignatures.remove(id);
    _visibleDialogGenerations.remove(id);
    _visibleDialogIds.remove(id);
  }

  void _reportFallbackIssue(
    int id,
    String? payload,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[ForegroundReminderPopupSink] fallback operation failed: '
      '$error\n$stackTrace',
    );
    final fallback = notificationFallback;
    if (fallback == null || fallback is! ReminderScheduleIssueSink) return;
    (fallback as ReminderScheduleIssueSink).recordReminderScheduleIssue(
      title: '弹出框提醒注册失败',
      message: '应用内弹窗的系统通知兜底未能更新：$error',
      relatedId: _relatedId(payload) ?? id.toString(),
    );
  }

  String? _relatedId(String? payload) {
    final uri = payload == null ? null : Uri.tryParse(payload);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    return uri.pathSegments.first == 'todo' && uri.pathSegments.length > 1
        ? uri.pathSegments[1]
        : uri.pathSegments.first;
  }

  DateTime _nextOccurrence(
    int hour,
    int minute,
    List<int>? weekdays,
    DateTime now,
  ) {
    now = AppClock.toLocal(now);
    var next = AppClock.date(now.year, now.month, now.day, hour, minute);
    final repeatDays = (weekdays ?? const <int>[])
        .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
        .toSet();
    while (!next.isAfter(now) ||
        (repeatDays.isNotEmpty && !repeatDays.contains(next.weekday))) {
      next = AppClock.date(next.year, next.month, next.day + 1, hour, minute);
    }
    return next;
  }

  bool _show({
    required int id,
    required String title,
    required String body,
    required String? payload,
  }) {
    if (!isForegroundGetter()) return false;
    final context = contextGetter();
    if (context == null || !context.mounted) return false;
    final signature = _popupSignature(
      title: title,
      body: body,
      payload: payload,
    );
    final generation = _generations[id];
    if (generation == null ||
        !_reserveVisibleDialog(
          id: id,
          signature: signature,
          generation: generation,
        )) {
      return false;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        _visibleNavigators[id] = Navigator.of(ctx, rootNavigator: true);
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
            if (payload != null && payload.isNotEmpty && onOpenPayload != null)
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onOpenPayload!(payload);
                },
                child: const Text('查看'),
              ),
          ],
        );
      },
    ).whenComplete(() {
      _clearVisibleDialogState(
        id,
        expectedSignature: signature,
        generation: generation,
      );
    });
    return true;
  }

  String _popupSignature({
    required String title,
    required String body,
    required String? payload,
  }) {
    return '$title\n$body\n${payload ?? ''}';
  }

  bool _reserveVisibleDialog({
    required int id,
    required String signature,
    required int generation,
  }) {
    final now = DateTime.now();
    _recentVisibleDialogSignatures.removeWhere(
      (_, at) => now.difference(at) > _visiblePopupDuplicateWindow,
    );
    if (_visibleDialogIds.contains(id)) return false;
    if (_visibleDialogSignatures.containsValue(signature)) return false;
    final lastShownAt = _recentVisibleDialogSignatures[signature];
    if (lastShownAt != null &&
        now.difference(lastShownAt) <= _visiblePopupDuplicateWindow) {
      return false;
    }
    _visibleDialogIds.add(id);
    _visibleDialogSignatures[id] = signature;
    _visibleDialogGenerations[id] = generation;
    _recentVisibleDialogSignatures[signature] = now;
    return true;
  }

  static bool _defaultIsForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }
}
