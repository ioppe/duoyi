import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PNG 文件头（原生只回传 PNG，Dart 侧据此拒绝损坏/截断的图标数据）。
const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// 分心监控状态。
///
/// 授权类字段（[accessGranted]、[accessibilityGranted]、[blockerConfigured]）
/// 只能由原生 `getStatus` 覆盖；轮询前台应用时用 [copyWith] / [withForeground]
/// 局部更新，避免把已授权状态误判成未授权。
@immutable
class FocusDistractionStatus {
  final bool supported;
  final bool accessGranted;

  /// 辅助功能拦截服务已在系统设置中启用（组件名规范化比较，兼容 `.Cls` 短名）。
  final bool accessibilityGranted;

  /// 系统 AccessibilityManager 已实际加载该服务（启用但未生效时为 false）。
  final bool accessibilityActive;
  final bool blockerConfigured;

  /// 原生 blocker 配置的过期时刻（epoch ms）；0/null 表示不过期（旧配置）。
  final int? blockerExpiresAtMs;
  final String? foregroundPackage;

  /// 最近一次原生拦截的分心应用与时间（epoch ms）。
  final String? lastBlockedPackage;
  final int? lastBlockedAtMs;

  const FocusDistractionStatus({
    required this.supported,
    required this.accessGranted,
    this.accessibilityGranted = false,
    this.accessibilityActive = false,
    this.blockerConfigured = false,
    this.blockerExpiresAtMs,
    this.foregroundPackage,
    this.lastBlockedPackage,
    this.lastBlockedAtMs,
  });

  const FocusDistractionStatus.unavailable()
    : supported = false,
      accessGranted = false,
      accessibilityGranted = false,
      accessibilityActive = false,
      blockerConfigured = false,
      blockerExpiresAtMs = null,
      foregroundPackage = null,
      lastBlockedPackage = null,
      lastBlockedAtMs = null;

  factory FocusDistractionStatus.fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const FocusDistractionStatus.unavailable();
    return FocusDistractionStatus(
      supported: raw['supported'] == true,
      accessGranted: raw['accessGranted'] == true,
      accessibilityGranted: raw['accessibilityGranted'] == true,
      accessibilityActive: raw['accessibilityActive'] == true,
      blockerConfigured: raw['blockerConfigured'] == true,
      blockerExpiresAtMs: _positiveIntOrNull(raw['blockerExpiresAt']),
      foregroundPackage: _nonEmptyStringOrNull(raw['foregroundPackage']),
      lastBlockedPackage: _nonEmptyStringOrNull(raw['lastBlockedPackage']),
      lastBlockedAtMs: _positiveIntOrNull(raw['lastBlockedAt']),
    );
  }

  /// 是否具备“拉回前台”能力；两者都缺时仍可用使用情况访问记录惩罚。
  bool get canBlockForeground => supported && accessibilityGranted;

  FocusDistractionStatus copyWith({
    bool? supported,
    bool? accessGranted,
    bool? accessibilityGranted,
    bool? accessibilityActive,
    bool? blockerConfigured,
    int? blockerExpiresAtMs,
    String? foregroundPackage,
    String? lastBlockedPackage,
    int? lastBlockedAtMs,
  }) {
    return FocusDistractionStatus(
      supported: supported ?? this.supported,
      accessGranted: accessGranted ?? this.accessGranted,
      accessibilityGranted: accessibilityGranted ?? this.accessibilityGranted,
      accessibilityActive: accessibilityActive ?? this.accessibilityActive,
      blockerConfigured: blockerConfigured ?? this.blockerConfigured,
      blockerExpiresAtMs: blockerExpiresAtMs ?? this.blockerExpiresAtMs,
      foregroundPackage: foregroundPackage ?? this.foregroundPackage,
      lastBlockedPackage: lastBlockedPackage ?? this.lastBlockedPackage,
      lastBlockedAtMs: lastBlockedAtMs ?? this.lastBlockedAtMs,
    );
  }

  /// 只更新前台应用：授权、拦截配置与最近拦截事件原样保留。
  FocusDistractionStatus withForeground(String? packageName) {
    return copyWith(
      accessGranted: accessGranted || packageName != null,
      foregroundPackage: packageName,
    );
  }
}

/// 原生无障碍服务“已拦截并拉回”的事件。
///
/// 快速弹回时使用情况轮询看不到分心应用的前台记录，必须消费原生事件补记，
/// 同时与轮询结果互相去重（同一包名只记一次，直到用户回到多仪）。
@immutable
class FocusNativeBlockEvent {
  final String packageName;
  final int blockedAtMs;

  const FocusNativeBlockEvent({
    required this.packageName,
    required this.blockedAtMs,
  });

  static FocusNativeBlockEvent? fromStatus(FocusDistractionStatus status) {
    final package = status.lastBlockedPackage?.trim() ?? '';
    final at = status.lastBlockedAtMs;
    if (package.isEmpty || at == null || at <= 0) return null;
    return FocusNativeBlockEvent(packageName: package, blockedAtMs: at);
  }

  /// 判定为 true 时调用方应写入一条分心惩罚并把 [blockedAtMs] 记为已消费。
  bool shouldRecord({
    required int lastConsumedBlockedAtMs,
    required String? lastRecordedPackage,
    required Iterable<String> blockedPackages,
    int notBeforeMs = 0,
  }) {
    if (blockedAtMs < notBeforeMs) return false;
    if (blockedAtMs <= lastConsumedBlockedAtMs) return false;
    if (!blockedPackages.contains(packageName)) return false;
    if (lastRecordedPackage == packageName) return false;
    return true;
  }
}

/// 原生 blocker 配置的有效期：进程被杀后不得永久拦截。
///
/// - 倒计时：失效时刻对齐本次会话结束（锚点即自然到期时刻）。
/// - 正计时：给出有限租约，Dart 侧周期续租；轮询停摆时最迟租约到期失效。
class FocusBlockerLease {
  FocusBlockerLease._();

  /// 正计时租约（秒）。
  static const int countUpLeaseSeconds = 2 * 60 * 60;

  /// 剩余有效期不足该值时续租。
  static const int renewalWindowSeconds = 120;

  static int expiresAtMs({
    required bool isCountUp,
    required int? activeAnchorMs,
    required int remainingSeconds,
    required int nowMs,
  }) {
    if (isCountUp) return nowMs + countUpLeaseSeconds * 1000;
    final anchor = activeAnchorMs;
    if (anchor != null && anchor > nowMs) return anchor;
    final remaining = remainingSeconds <= 0 ? 0 : remainingSeconds;
    return nowMs + remaining * 1000;
  }

  static bool needsRenewal({required int? expiresAtMs, required int nowMs}) {
    if (expiresAtMs == null || expiresAtMs <= 0) return true;
    return expiresAtMs - nowMs <= renewalWindowSeconds * 1000;
  }
}

/// 一个可启动的已安装应用。
///
/// [iconBytes] 是原生在工作线程渲染出的 PNG 图标字节；缺失或不是合法 PNG 时为
/// null，调用方必须回退到占位图标而不是显示破图。
@immutable
class InstalledFocusApp {
  final String label;
  final String packageName;
  final bool isSystemApp;
  final Uint8List? iconBytes;

  const InstalledFocusApp({
    required this.label,
    required this.packageName,
    this.isSystemApp = false,
    this.iconBytes,
  });

  String get displayLabel {
    final clean = label.trim();
    return clean.isEmpty ? packageName : clean;
  }

  bool get hasIcon => iconBytes != null && iconBytes!.isNotEmpty;

  /// 解析原生返回的一条应用记录；缺包名的记录直接丢弃，其余保持原生顺序。
  static InstalledFocusApp? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    final packageName = raw['packageName']?.toString().trim() ?? '';
    if (packageName.isEmpty) return null;
    return InstalledFocusApp(
      label: raw['label']?.toString().trim() ?? '',
      packageName: packageName,
      isSystemApp: raw['isSystemApp'] == true,
      iconBytes: _validPngBytes(raw['iconBytes']),
    );
  }
}

Uint8List? _validPngBytes(Object? raw) {
  final Uint8List bytes;
  if (raw is Uint8List) {
    bytes = raw;
  } else if (raw is List<int>) {
    bytes = Uint8List.fromList(raw);
  } else {
    return null;
  }
  if (bytes.length < _pngSignature.length) return null;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return null;
  }
  return bytes;
}

int? _positiveIntOrNull(Object? raw) {
  final value = switch (raw) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v.trim()),
    _ => null,
  };
  if (value == null || value <= 0) return null;
  return value;
}

String? _nonEmptyStringOrNull(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

class FocusDistractionService {
  FocusDistractionService._();

  static final FocusDistractionService instance = FocusDistractionService._();
  static const MethodChannel _channel = MethodChannel(
    'duoyi/focus_distraction',
  );

  Future<FocusDistractionStatus> getStatus() async {
    if (!_isAndroid) return const FocusDistractionStatus.unavailable();
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getStatus');
      return FocusDistractionStatus.fromMap(raw);
    } catch (e, st) {
      debugPrint('[FocusDistractionService] getStatus failed: $e\n$st');
      return const FocusDistractionStatus.unavailable();
    }
  }

  Future<String?> getForegroundApp() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getForegroundApp');
    } catch (e, st) {
      debugPrint('[FocusDistractionService] foreground app failed: $e\n$st');
      return null;
    }
  }

  /// 包名 → 应用显示名；解析失败返回 null，调用方回退到包名。
  Future<String?> getAppLabel(String packageName) async {
    final clean = packageName.trim();
    if (!_isAndroid || clean.isEmpty) return null;
    try {
      final label = await _channel.invokeMethod<String>('getAppLabel', {
        'packageName': clean,
      });
      final trimmed = label?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (e, st) {
      debugPrint('[FocusDistractionService] app label failed: $e\n$st');
      return null;
    }
  }

  /// 扫描可启动的已安装应用。仅 Android 支持；失败时返回空列表，
  /// 调用方需把空列表当作“无法解析”而不是“没有任何应用”。
  Future<List<InstalledFocusApp>> getInstalledApps() async {
    if (!_isAndroid) return const <InstalledFocusApp>[];
    try {
      final raw = await _channel.invokeListMethod<Object?>('getInstalledApps');
      if (raw == null) return const <InstalledFocusApp>[];
      final apps = <InstalledFocusApp>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final app = InstalledFocusApp.fromMap(entry);
        if (app != null) apps.add(app);
      }
      return List.unmodifiable(apps);
    } catch (e, st) {
      debugPrint('[FocusDistractionService] installed apps failed: $e\n$st');
      return const <InstalledFocusApp>[];
    }
  }

  Future<bool> openUsageAccessSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openUsageAccessSettings') ??
          false;
    } catch (e, st) {
      debugPrint('[FocusDistractionService] open settings failed: $e\n$st');
      return false;
    }
  }

  Future<bool> openAccessibilitySettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAccessibilitySettings') ??
          false;
    } catch (e, st) {
      debugPrint(
        '[FocusDistractionService] open accessibility failed: $e\n$st',
      );
      return false;
    }
  }

  /// 写入原生拦截配置。[expiresAtMs] 为配置失效时刻（epoch ms）；
  /// null/0 表示不过期，仅用于兼容旧配置，正常调用必须给出有限时间。
  Future<bool> setFocusBlocker({
    required bool enabled,
    required List<String> packages,
    int? expiresAtMs,
  }) async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('setFocusBlocker', {
            'enabled': enabled,
            'packages': packages,
            'expiresAtMs': expiresAtMs,
          }) ??
          false;
    } catch (e, st) {
      debugPrint('[FocusDistractionService] set blocker failed: $e\n$st');
      return false;
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
