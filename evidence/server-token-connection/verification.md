# 服务器地址与访问令牌连接验证

## 完成行为

- 安装端默认显示服务器地址与访问令牌表单，保留账号密码、邮箱登录和注册入口。运行时地址可持久化；构建值仅提供初始地址。
- Web 默认使用当前站点 origin 的 API 与 WebSocket，不使用安装端的已保存地址或构建服务器覆盖。旧版未绑定服务器的会话只在原构建服务器与当前目标一致时迁移。
- 个人资料的账号安全区新增“访问令牌”：创建、一次性显示与复制、命名、可选有效期、最近使用时间、当前设备标记及撤销。
- SQLite 持久化令牌摘要，完整秘密仅在创建响应返回；普通登录不会替换设备令牌。账号安全变更撤销相应令牌，HTTP、WebSocket 与排行 SSE 均检查凭据有效性。
- 新令牌先验证再切换。服务器与账号共同决定数据归属；账号清理、登录及退出提交串行执行，旧请求不会把凭据或账号状态应用到新服务器。相对头像、AI、共享、同步、专注和后端更新策略跟随当前连接。
- Android 与 iOS 允许用户明确填写 HTTP 自托管地址，默认实例仍为 HTTPS，证书验证不绕过。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 全部后端 unittest | 225 项通过，含 36 项访问令牌测试 |
| Flutter 相关回归 | 193 项通过 |
| Flutter analyze | 0 issues |
| 全部静态保护测试（96 个文件） | 333 项通过，1 项既有失败，见下文 |
| Web release 构建 | 成功，Flutter 3.44.1 / Dart 3.12.1 |
| 真实后端进程重启验证 | 创建 PAT → 访问账号 → 重启进程 → 仍可访问 → 当前标记/最近使用时间正确 → 撤销 → 重用返回 401 |
| 本地浏览器 | Web 账号登录、个人资料令牌入口、创建、复制按钮、列表和撤销状态验证完成；所有 API 请求来自当前 origin |
| 安装端渲染 | 手机 390×844、桌面 1280×820 登录表单及令牌列表，3 项截图辅助测试通过，无布局异常 |
| 配置与文件检查 | 公开配置验证、iOS plist、Android XML、git diff --check 通过 |

浏览器环境禁止读取剪贴板；已触发复制操作，未声称读回验证剪贴板内容。截图使用示例元数据，无有效访问令牌。

### 既有测试失败

`test/screens/todo_batch_static_test.dart:122` 要求 `_TodoViewMode.list =>` 后的精确换行格式，与 `lib/screens/todo_screen.dart:909` 的现有格式不一致。这两个文件与原 HEAD 字节完全相同，本次未改动；未放宽或跳过保护测试。全部静态保护本轮为 333 通过、1 失败。

未构建或真机验证 iOS、Windows、macOS 安装包。本次完成共享 Flutter 连接流程、平台网络配置、相关组件与 Web 的验证，不代表各平台安装包已经发布。

## 关键回归用例

- 不同服务器返回相同用户 ID、甚至相同令牌文本时，仍正确清理并绑定新服务器数据归属。
- 令牌验证失败保留原客户端、凭据与本地数据；存储绑定不匹配时不恢复旧凭据。
- 密码登录、邮箱登录和注册的延迟响应不能覆盖后续 PAT 登录；账号清理期间后续提交等待；延迟撤销响应不能清理新会话。
- 旧服务器配置与 401 响应不会覆盖/登出新连接；新服务器相对头像正确解析；切换后更新策略会排队重新检查。
- PAT 创建与撤销/改密并发时，在同一数据库事务内重新认证；仅有 PAT 的设备计入在线状态；已建立 SSE/WS 在凭据失效后停止后续输出。

## 复现命令

从仓库根目录、在隔离数据库与适配工具链环境中执行：

```bash
DUOYI_DB_PATH="$PI_SCRATCH_DIR/duoyi-token-backend-suite.db" \
DUOYI_ENV_FILE= APP_UPDATE_REPOSITORY= PYTHONDONTWRITEBYTECODE=1 \
TMPDIR="$PI_SCRATCH_DIR" "$PYTHON_BIN" -m unittest discover -s backend -v

flutter analyze --no-pub
TZ=UTC flutter test --no-pub \
  test/providers/server_connection_test.dart \
  test/providers/server_connection_race_test.dart \
  test/services/app_update_connection_test.dart \
  test/screens/access_tokens_screen_test.dart \
  test/screens/login_screen_test.dart \
  test/providers/auth_provider_profile_test.dart \
  test/providers/auth_provider_profile_static_test.dart \
  test/services/app_update_service_test.dart \
  test/services/api_client_error_test.dart \
  test/core/flutter_l10n_static_test.dart \
  test/core/i18n_test.dart \
  test/services/no_global_bold_static_test.dart \
  test/services/cloud_sync_provider_test.dart \
  test/screens/profile_screen_test.dart \
  test/services/android_network_security_static_test.dart \
  test/services/api_route_contract_static_test.dart

python3 scripts/flutter_with_config.py build web --release --no-pub
python3 scripts/project_config.py validate
```

实际 Flutter 验证在等价 ASCII 临时副本中运行，避免主机中文目录的已知 analyzer 协议异常；未把测试账号、数据库或有效令牌加入仓库。

API 契约：`2026-06-01.3`，required routes 63 条，hash `48881df2412c4ae0`。

[界面截图预览](../screenshots/server-token-connection/index.html) · [安装端手机登录](../screenshots/server-token-connection/token-login-mobile.png) · [安装端桌面登录](../screenshots/server-token-connection/token-login-desktop.png) · [令牌管理](../screenshots/server-token-connection/token-manager.png)

所有变更留在本地工作树，包含前一轮配置重构；未提交、未推送、未部署至生产环境，现有线上数据库及服务未修改。
