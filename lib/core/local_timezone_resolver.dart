import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'platform_info.dart';

/// 统一的本地时区解析器。
///
/// 调用顺序：
/// 1. 用户显式固定应用内时区时使用该 IANA 名
/// 2. 默认跟随手机系统 IANA 时区（例：`America/Mexico_City`）
/// 3. `flutter_timezone` 只返回 `UTC` 或不可解析值时，读取 Android 原生
///    `TimeZone.getDefault().id`
/// 4. 原生时区也不可用时，再尝试 Dart 侧 `DateTime.timeZoneName`
/// 5. 仍不可用时按手机当前 offset 推断 `Etc/GMT`
/// 6. offset 也不可用时才回退 `Asia/Shanghai`
///
/// 任何"什么时候响"的调度代码必须使用 `tz.TZDateTime.from(dateTime, tz.local)`，
/// 禁止直接 `DateTime.utc(...)` 传入 `zonedSchedule`。
class LocalTimezoneResolver {
  LocalTimezoneResolver._();

  static const String preferenceKey = 'pref_app_timezone_iana';
  static const String modePreferenceKey = 'pref_app_timezone_mode';
  static const String defaultIana = 'Asia/Shanghai';
  static const String followSystemValue = 'system';
  static const String fixedValue = 'fixed';

  @visibleForTesting
  static Future<String?> Function()? debugSystemTimeZoneReader;

  @visibleForTesting
  static Future<String?> Function()? debugNativeSystemTimeZoneReader;

  static bool get _hasDebugTimeZoneReaders =>
      debugSystemTimeZoneReader != null ||
      debugNativeSystemTimeZoneReader != null;

  /// 非理想路径的日志（`flutter_timezone` 失败 / 回退次数等），便于 QA 排查。
  static final List<String> diagnostics = [];

  static bool _initialized = false;
  static String _currentIana = defaultIana;
  static final ValueNotifier<String> timezoneListenable = ValueNotifier(
    defaultIana,
  );

  /// 解析出的 IANA 名，例如 `Asia/Shanghai`。
  static String get currentIana => _currentIana;

  /// 是否已初始化（`init()` 是否被调用过）。
  static bool get isInitialized => _initialized;

  /// 初始化时区数据库并设置 `tz.local`。幂等调用。
  ///
  /// 应在 `runApp` 之前、`main()` 初始化阶段调用一次。
  static Future<void> init() async {
    // tz 数据库是进程级全局的，允许多次调用，但只有第一次生效。
    tzdata.initializeTimeZones();

    final name = await _resolveIanaName();
    _setLocation(name);
    _initialized = true;
  }

  /// 重新探测并应用当前系统时区。返回新的 IANA 名。
  ///
  /// 用于 `AppLifecycleState.resumed` 时对比缓存值，若变化则触发
  /// `ReminderScheduler.resyncAll`。
  static Future<String> refresh() async {
    if (!_initialized) tzdata.initializeTimeZones();
    final name = await _resolveIanaName();
    _setLocation(name);
    return _currentIana;
  }

  static Future<void> setApplicationTimeZone(String name) async {
    tzdata.initializeTimeZones();
    final p = await SharedPreferences.getInstance();
    if (name == followSystemValue) {
      await p.setString(modePreferenceKey, followSystemValue);
      await p.remove(preferenceKey);
      final resolved = await _resolveIanaName();
      _setLocation(resolved);
      _initialized = true;
      return;
    }
    final next = _canResolve(name) ? name : defaultIana;
    await p.setString(modePreferenceKey, fixedValue);
    await p.setString(preferenceKey, next);
    _setLocation(next);
    _initialized = true;
  }

  static Future<String> _resolveIanaName() async {
    try {
      final p = await SharedPreferences.getInstance();
      final mode = p.getString(modePreferenceKey) ?? followSystemValue;
      final saved = p.getString(preferenceKey);
      if (mode == fixedValue &&
          saved != null &&
          saved.isNotEmpty &&
          _canResolve(saved)) {
        return saved;
      }

      final systemName = await _readSystemIanaName();
      if (systemName != null) return systemName;
      if (_hasDebugTimeZoneReaders) {
        _log(
          'debug timezone readers resolved no usable non-UTC zone; fallback to $defaultIana',
        );
        return defaultIana;
      }

      final offset = DateTime.now().timeZoneOffset;
      if (offset == Duration.zero) return 'UTC';
      final offsetName = _offsetBasedIanaName(offset);
      if (offsetName != null) {
        _log('系统时区不可用，按手机 offset 推断为 $offsetName');
        return offsetName;
      }

      _log('系统时区和 offset 均不可用，回退到 $defaultIana');
      return defaultIana;
    } catch (e) {
      _log('解析应用时区失败: $e，回退到 $defaultIana');
      return defaultIana;
    }
  }

  static Future<String?> _readSystemIanaName() async {
    String? utcCandidate;
    final debugReader = debugSystemTimeZoneReader;
    if (debugReader != null) {
      try {
        final debugName = await debugReader();
        final normalizedDebugName = _normalizeSystemName(debugName);
        if (normalizedDebugName != null && _canResolve(normalizedDebugName)) {
          utcCandidate = normalizedDebugName;
        }
        if (_isUsableIana(normalizedDebugName)) return normalizedDebugName;
        if (debugName != null) {
          _log('测试注入的系统时区不可用: "$debugName"');
        }
      } catch (_) {
        // 测试注入失败时继续走真实平台。
      }
    } else {
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        final normalizedName = _normalizeSystemName(name);
        if (normalizedName != null && _canResolve(normalizedName)) {
          utcCandidate = normalizedName;
        }
        if (_isUsableIana(normalizedName)) return normalizedName;
        _log('flutter_timezone 返回不可用时区: "$name"');
      } catch (e) {
        _log('flutter_timezone.getLocalTimezone 异常: $e');
      }
    }

    final nativeName = await _readNativeSystemIanaName();
    if (nativeName != null) return nativeName;
    if (utcCandidate != null) return utcCandidate;

    final dartName = DateTime.now().timeZoneName;
    final normalizedDartName = _normalizeSystemName(dartName);
    if (_isUsableIana(normalizedDartName)) return normalizedDartName;
    _log('DateTime.timeZoneName 不可用: "$dartName"');
    return null;
  }

  static Future<String?> _readNativeSystemIanaName() async {
    final debugReader = debugNativeSystemTimeZoneReader;
    if (debugReader != null) {
      try {
        final debugName = await debugReader();
        final normalizedDebugName = _normalizeSystemName(debugName);
        if (_isUsableIana(normalizedDebugName)) return normalizedDebugName;
        if (debugName != null) {
          _log('测试注入的原生系统时区不可用: "$debugName"');
        }
      } catch (_) {
        // 测试注入失败时继续走真实平台。
      }
      return null;
    }

    try {
      final name = await PlatformInfo.getSystemTimeZoneId();
      final normalizedName = _normalizeSystemName(name);
      if (_isUsableIana(normalizedName)) return normalizedName;
      if (name != null) {
        _log('Android 原生系统时区不可用: "$name"');
      }
    } catch (e) {
      _log('读取 Android 原生系统时区异常: $e');
    }
    return null;
  }

  static String? _normalizeSystemName(String? name) {
    if (name == null) return null;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    if (_canResolve(trimmed)) return trimmed;
    final upper = trimmed.toUpperCase();
    const aliases = <String, String>{
      'MEXICO CITY': 'America/Mexico_City',
      'CENTRAL STANDARD TIME (MEXICO)': 'America/Mexico_City',
      'CENTRAL DAYLIGHT TIME (MEXICO)': 'America/Mexico_City',
      'MOUNTAIN STANDARD TIME (MEXICO)': 'America/Chihuahua',
      'PACIFIC STANDARD TIME (MEXICO)': 'America/Tijuana',
      'CHINA STANDARD TIME': 'Asia/Shanghai',
      'HONG KONG STANDARD TIME': 'Asia/Hong_Kong',
      'TAIPEI STANDARD TIME': 'Asia/Taipei',
    };
    return aliases[upper];
  }

  static String? _offsetBasedIanaName(Duration offset) {
    if (offset.inMinutes == 0) return null;
    if (offset.inMinutes % 60 != 0) return null;
    final hours = offset.inHours;
    if (hours < -14 || hours > 14) return null;
    final sign = hours >= 0 ? '-' : '+';
    final name = 'Etc/GMT$sign${hours.abs()}';
    return _canResolve(name) ? name : null;
  }

  static bool _isUsableIana(String? name) {
    if (name == null || name.isEmpty || _isUtcLike(name)) return false;
    return _canResolve(name);
  }

  static bool _isUtcLike(String name) {
    final upper = name.trim().toUpperCase();
    return upper == 'UTC' ||
        upper == 'ETC/UTC' ||
        upper == 'GMT' ||
        upper == 'ETC/GMT' ||
        upper == 'Z';
  }

  static bool _canResolve(String name) {
    try {
      tz.getLocation(name);
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _setLocation(String name) {
    _initialized = true;
    try {
      tz.setLocalLocation(tz.getLocation(name));
      _currentIana = name;
    } catch (e) {
      _log('setLocalLocation 失败(name=$name): $e，强制使用 $defaultIana');
      final fallback = tz.getLocation(defaultIana);
      tz.setLocalLocation(fallback);
      _currentIana = defaultIana;
    }
    if (timezoneListenable.value != _currentIana) {
      timezoneListenable.value = _currentIana;
    }
  }

  static void _log(String msg) {
    diagnostics.add(msg);
    if (kDebugMode) {
      debugPrint('[LocalTimezoneResolver] $msg');
    }
  }
}
