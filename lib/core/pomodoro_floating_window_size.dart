/// macOS 番茄悬浮窗的卡片尺寸。
///
/// 这是设备本地的外观偏好：不同 Mac 的屏幕空间差异很大，因此不进入云同步
/// 白名单，只保存在 `SharedPreferences`。
///
/// [storageValue] 是与原生面板（`macos/Runner/PomodoroFloatingPanel.swift`）
/// 约定的通道字段值，显式声明而不依赖 `name`，避免枚举重命名破坏旧版本兼容。
enum PomodoroFloatingWindowSize {
  /// 现有卡片：主按钮同时显示图标与本地化文字。
  large('large'),

  /// 紧凑卡片：仅图标按钮，适合小屏或角落常驻。
  compact('compact');

  const PomodoroFloatingWindowSize(this.storageValue);

  /// 持久化与原生通道使用的稳定字符串。
  final String storageValue;

  /// 未配置、旧数据或无法识别时的默认尺寸。
  static const PomodoroFloatingWindowSize defaultSize =
      PomodoroFloatingWindowSize.large;

  /// 容错解析：缺失、空串或未知值一律回退 [defaultSize]，
  /// 避免脏数据让悬浮窗改用不可预期的布局。
  static PomodoroFloatingWindowSize parse(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return defaultSize;
    for (final size in values) {
      if (size.storageValue == value) return size;
    }
    return defaultSize;
  }
}
