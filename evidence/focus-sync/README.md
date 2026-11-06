# 同账号多端专注同步：验证记录

开发分支：`feature/account-focus-sync`。工作区：`duoyi-focus-sync-feature`。

分支从获取到的 `origin/main` 建立，基线及当前 HEAD 为 `4602528a49191b5e3bae2f32b8603fc8956f42ef`。本次实现仍是未提交的工作区改动，未推送、部署或发布；不能只用 HEAD 哈希代替本次源码快照。

协议与兼容边界见 [同账号多端专注同步](../../docs/focus-runtime-sync.md)，人工场景见 [回归清单](../../docs/manual-regression-checklist.md)。

## 已执行结果

| 检查 | 实际结果 | 范围 |
| --- | --- | --- |
| 后端定向单元/API/契约 | **92 项通过** | 状态机、CAS、幂等、唯一结算、云同步并发、多普通登录、双 WS、凭据撤销、SQLite 迁移、路由契约 |
| Flutter 定向单元/Widget/静态守卫 | **215 项通过** | 下列 20 个测试文件；包括远端投影、重连、迟到响应、历史水合、idle 草稿、悬浮窗和 Android 控制 |
| 正式 Flutter 分析 | **No issues found** | Flutter 3.44.1，哈希一致的 ASCII 物理副本，`flutter analyze --no-pub`，耗时 7.8 秒 |
| 原路径 Dart 分析 | 通过 | `dart analyze lib` 曾用于确认 LSP 路径故障；最终源码以正式副本分析为准 |
| Swift 面板类型检查 | 通过 | `swiftc -swift-version 5 -typecheck macos/Runner/PomodoroFloatingPanel.swift`；不是完整 Runner 构建或启动验证 |
| 本地化生成 | 通过 | 5 组同步状态中英文条目及生成文件 |
| Diff 空白检查 | 通过 | `git diff --check` |

一次集中代码复审发现的具体问题已修正：清理备份保留递增 revision；idle 选择保留服务器控件绑定；失败的任务更新释放草稿；严格停止保留重置处罚；启动水合使用同一个 Future。文档核对要求的 Android 控制说明也已补齐。

## 复现定向测试

使用 `config/toolchain.json` 约束的 Flutter 3.44.1 / Python 3.12；后端验证在安装了 `backend/requirements.txt` 的独立环境内执行。下列变量指向对应可执行文件。

```bash
cd backend
"$PYTHON_BIN" -m unittest \
  test_focus_runtime test_login_sessions test_access_tokens test_login_session_store \
  test_workspaces.WorkspaceApiTest.test_public_health_and_config_include_api_contract \
  test_workspaces.WorkspaceApiTest.test_api_contract_required_routes_are_registered -v
cd ..

"$FLUTTER_BIN" test --no-pub \
  test/providers/pomodoro_remote_runtime_test.dart \
  test/services/focus_runtime_api_test.dart \
  test/services/focus_sync_coordinator_test.dart \
  test/services/focus_runtime_background_control_test.dart \
  test/widgets/focus_sync_status_test.dart \
  test/services/pomodoro_remote_floating_window_test.dart \
  test/providers/pomodoro_provider_test.dart \
  test/providers/pomodoro_notification_control_test.dart \
  test/providers/pomodoro_distraction_lifecycle_test.dart \
  test/services/pomodoro_floating_window_service_test.dart \
  test/widgets/pomodoro_floating_window_host_test.dart \
  test/services/home_widget_focus_control_test.dart \
  test/services/account_local_data_cleaner_test.dart \
  test/core/i18n_test.dart \
  test/screens/pomodoro_focus_layout_static_test.dart \
  test/screens/pomodoro_strict_focus_static_test.dart \
  test/services/rounded_typography_static_test.dart \
  test/screens/pomodoro_task_link_test.dart \
  test/widgets/pomodoro_task_picker_test.dart \
  test/services/android_widget_resources_test.dart --reporter expanded
```

## 分析副本与源码绑定

原中文路径中的 `flutter analyze` 在 LSP 初始化消息解析时报 `FormatException: Unterminated string`，退出码 255，错误包含百分号编码的中文目录。没有修改 SDK 或全局 Flutter 配置。

按 `flutter-ascii-source-verification` 流程创建新的 ASCII **物理目录**：复制 Git 跟踪和未忽略的新文件，排除 `.git`、`evidence`、忽略的构建输出和私有配置。复制时和分析后均逐文件复核。

- 校验普通文件：**1290**；原目录不匹配 **0**；副本不匹配 **0**；源码符号链接 **0**。
- 应用标识改动：**0**，未使用隔离 APK 模式，未构建或安装 APK。
- 副本执行 `flutter pub get --offline --enforce-lockfile` 后完成正式分析。
- `pubspec.lock` SHA-256（原目录、副本均保持）：`f8d521ef9f8b6a0673d1e8ec51064f71b1a71dcfa8253fe4cee25df6c409db7b`。
- 完整分析快照清单 SHA-256：`3d42211323385782bfa2b2d76bd4a4107b6e554c341583b983d724f96dbdf726`。

完整日志和清单保留在本会话 scratch：`focus-backend-final.log`、`focus-flutter-final.log`、`focus-flutter-analysis-final.log`、`focus-ascii-final-source-manifest.json`。分析后的仓库改动仅为本验证记录，以及 `docs/android-focus-updates.md` 的 HTTP 读取/提交描述修正；产品源码和锁文件保持冻结。上述 1290 项对应分析时的快照。

## 未执行范围

- Android 与 macOS 的真实双设备端到端操作、系统挂起/恢复、真实悬浮窗可见性与拖动；人工清单保持未勾选。
- 完整 macOS Runner 构建/启动、Android 安装包构建、签名、发布和线上部署。
- 全仓 Flutter/后端测试与 E2E 套件。

实时同步保证针对在线进程；退出或被系统挂起的客户端在恢复后通过权威快照收敛，不承诺未实现的推送唤醒。实际启用需要后端和各客户端运行包含该协议的版本；访客及明确不支持的旧后端保留本地模式。
