/// 特性开关（Task 23.1 / Requirements 12.6）。
///
/// 集中管理可回滚的特性开关；当前主要功能默认开启。
/// CI / QA 构建可以通过 `FeatureFlags.override(...)` 覆盖。
///
/// 后续如需按用户/租户/Remote Config 动态控制，可以在此基础上加
/// `SharedPreferences` 持久化或 `RemoteConfig` 拉取，对外 API 保持不变。
library;

class FeatureFlags {
  FeatureFlags._();

  // -----------------------
  // 静态默认值
  // -----------------------

  /// 后端 CloudSync v2 契约：Goal/Todo 字段对齐、排队重试。
  /// 默认开启；关闭时仍可使用本地数据，但不发出个人数据同步请求。
  static const bool _kCloudSyncV2Default = true;

  /// 多次提醒 v2：ReminderRule / ReminderPlan 及新编辑器。
  static const bool _kMultiReminderV2Default = true;

  /// 时间足迹 v1：TimeEntry、时间审计页和统计聚合。
  static const bool _kTimeAuditV1Default = true;

  /// 共享空间 v1：Workspace、邀请和共享清单/日程。
  static const bool _kWorkspaceShareV1Default = true;

  // -----------------------
  // 可覆盖层
  // -----------------------

  static bool? _cloudSyncV2Override;
  static bool? _multiReminderV2Override;
  static bool? _timeAuditV1Override;
  static bool? _workspaceShareV1Override;

  /// 当前是否开启 cloud_sync_v2。
  static bool get cloudSyncV2 => _cloudSyncV2Override ?? _kCloudSyncV2Default;

  /// 当前是否开启 multi_reminder_v2。
  static bool get multiReminderV2 =>
      _multiReminderV2Override ?? _kMultiReminderV2Default;

  /// 当前是否开启 time_audit_v1。
  static bool get timeAuditV1 => _timeAuditV1Override ?? _kTimeAuditV1Default;

  /// 当前是否开启 workspace_share_v1。
  static bool get workspaceShareV1 =>
      _workspaceShareV1Override ?? _kWorkspaceShareV1Default;

  /// 运行时覆盖（给 QA / 集成测试用）；传 null 恢复到默认值。
  static void overrideCloudSyncV2(bool? value) {
    _cloudSyncV2Override = value;
  }

  static void overrideMultiReminderV2(bool? value) {
    _multiReminderV2Override = value;
  }

  static void overrideTimeAuditV1(bool? value) {
    _timeAuditV1Override = value;
  }

  static void overrideWorkspaceShareV1(bool? value) {
    _workspaceShareV1Override = value;
  }

  /// 清空所有覆盖层（主要给单元测试用）。
  static void resetAllOverrides() {
    _cloudSyncV2Override = null;
    _multiReminderV2Override = null;
    _timeAuditV1Override = null;
    _workspaceShareV1Override = null;
  }
}
