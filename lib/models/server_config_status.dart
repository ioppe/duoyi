/// `/api/config` 的拉取状态，AuthProvider 与 AiService 共用。
///
/// 只有 [ready] 才代表「已经拿到服务端的真实开关」；[unknown] / [loading] /
/// [failed] 都**不能**被解释成「管理员关闭了 AI 或云备份」。旧实现只会把
/// 配置存在内存里，未加载时 AI 一律显示成管理员禁用，本枚举用来把这三态分开。
enum ServerConfigStatus {
  /// 还没发起过配置请求（冷启动首帧、刚切服务器）。
  unknown,

  /// 正在请求 `/api/config`。
  loading,

  /// 已成功拿到配置；此时服务端开关才有意义。
  ready,

  /// 请求失败（离线/超时/服务端错误）；保留同连接上一次成功的配置。
  failed,
}
