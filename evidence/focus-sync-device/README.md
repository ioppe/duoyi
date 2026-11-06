# 同账号多端专注：实机测试记录

本轮在连接的小米手机上完成了 **11/11 项实机断言**，并在测试过程中修复了真实冷启动崩溃与后端 WebSocket 运行依赖缺失。

测试使用独立应用 **多仪·同步验证**（`com.duoyi.duoyi.accountfocuscheck`）、独立 SQLite 数据库和新建测试账号；手机上的正式应用保持不变。第二客户端为 Mac 上运行的同源 Flutter Web，原生 macOS 面板另做独立检查，**未将这两项合称为完整 Android ↔ macOS Flutter 客户端验收**。

## 候选与环境

| 项目 | 实际值 |
| --- | --- |
| 工作分支 | `feature/account-focus-sync`，未提交的工作区改动 |
| 开发起点 | 创建分支时获取的 main `4602528a49191b5e3bae2f32b8603fc8956f42ef`；测试期间 origin/main 已有后续提交，本轮未合并它们 |
| 手机 | Xiaomi 24129PN74C，Android 16 / API 36，arm64-v8a |
| 屏幕 | 1200×2670，520 dpi，字体缩放 1.25；测试前后相同 |
| 验证包版本 | 2.0.0 / 140023，debug 签名，独立包名 |
| **最终实测 APK SHA-256** | `377aa209fb8a12df7e35988a106c93ed97edc049c91e748187da17c8bfdff7be` |
| 最终 APK 大小 | 160,626,934 bytes |
| 测试后端 | 真实 FastAPI / Uvicorn，`http://127.0.0.1:18791`；手机通过仅测试用 ADB reverse 连接 |
| 账号 | 专用 `focus-device-test`，手机与第二端使用不同普通登录令牌；凭据仅在 scratch 保存 |
| 时长夹具 | 专注、短休、长休各 60 秒；自动轮转开关关闭；声音、勿扰与严格拦截关闭 |
| 工具链 | Flutter 3.44.1、JDK 17、Python 3.12.14 |

候选包和源码更新绑定见 [最终候选元数据](candidate-fixed.json)。最终包是在最初 1290 文件哈希快照上更新已校验的 Kotlin 修复、依赖清单与协议说明后重建；Dart 源码未改变。两份未完成的全量复制没有用作验收候选。设备实际安装 APK 的哈希也已核对为上述值。

## 最终实机结果

最终测试窗口：2026-11-06 18:54:57–18:57:36（设备本地时间），共约 159 秒。所有断言来自同一个最终 APK 的完整运行，未拼接旧包的通过结果，未跳过用例。

| 用例 | 结果 | 断言与证据 |
| --- | --- | --- |
| 01 两个普通登录与连接状态 | PASS | 同一账号的两个独立令牌有效；手机显示已同步。[就绪画面](../screenshots/focus-sync-device/10-ready.png) |
| 02 手机开始，第二端收到 | PASS | 手机按钮发起 60 秒专注，来源设备正确，同一 session/revision 向第二端 WS 发送。[手机](../screenshots/focus-sync-device/11-phone-start.png) · [第二端运行画面](web-shared-session.jpg) |
| 03 远端暂停，手机冻结 | PASS | 第二端凭据提交暂停，手机冻结于 `00:56`，至少 8 秒不变。[暂停](../screenshots/focus-sync-device/12-remote-pause.png) · [等待后](../screenshots/focus-sync-device/13-pause-frozen.png) |
| 04 远端任务修改 | PASS | 手机可见 `SYNC-REMOTE-TASK`。[任务画面](../screenshots/focus-sync-device/14-remote-task.png) |
| 05 手机继续 | PASS | 保留同一 session，revision 推进，第二端收到 running 状态 |
| 06 手机重置 | PASS | 返回 idle、更换 session；被重置的这场没有完成记录。已有测试历史保留 |
| 07 结束进程后恢复 | PASS | 强制结束验证包进程，服务端继续计时；重开手机恢复同一 session，显示 `00:44`。[恢复画面](../screenshots/focus-sync-device/15-restart-restored.png) |
| 08 自然到期与唯一结算 | PASS | 转入短休；该 session 在服务端恰好一条历史和一条 `pomodoro:<sessionId>` 时间足迹。[到期画面](../screenshots/focus-sync-device/16-natural-completion.png) |
| 09 正计时主动完成 | PASS | 手机选择自由计时并开始/完成；按有效时长结算 12 秒，历史与时间足迹均只一条。[正计时](../screenshots/focus-sync-device/17-countup.png) · [完成](../screenshots/focus-sync-device/18-countup-completed.png) |
| 10 后端不可达时冷启动 | PASS | 仅移除测试端口 reverse；控制禁用，不产生独立本地计时或服务端命令。[离线画面](../screenshots/focus-sync-device/19-offline-cold-start.png) |
| 11 恢复连接、不重放旧操作 | PASS | 恢复 reverse 后显示已同步；session/revision 保持不变，没有重放控制。[最终画面](../screenshots/focus-sync-device/20-reconnected-final.png) |

完整逐项记录：[physical-results.json](physical-results.json)。其中远端暂停/任务修改的自动化用例使用第二端令牌调用真实命令接口，再核对手机投影与第二端 WS；另在初始包诊断时，实际点击过第二端 Flutter Web 的暂停按钮，手机同样冻结，画面保留于 [初始包双端界面暂停](pre-fix-screenshots/21-web-ui-paused-phone.png)。这些记录分别标明了触发方式。

测试后的验证包停留在专注页，显示“多端专注已同步”、`01:00` 空闲休息阶段及测试任务。本地测试服务与 USB 18791 映射保留，便于继续手动验证；原先的 18781 映射也已恢复。

## 实测发现与修复

### Android 冷启动前台服务崩溃

初始 APK `89a8581411e093289c4570a800ea8e864bbf26629fcbd0fdb6f630d72280742a` 的前 6 项通过，但重启恢复时真实发生 `ForegroundServiceDidNotStartInTimeException`，进程退出回到启动器。

[初始失败结果](physical-pre-fix-crash.json) · [限定该进程的崩溃栈](pre-fix-foreground-service-crash.txt)。初始 APK、完整日志和其余原始截图在本会话 scratch 保留。

修复 `FocusTimerForegroundService`：

- `onCreate` 先用应用名和固定标志建立最小前台通知，立即履行系统前台提升要求，随后按计时载荷更新。
- 停止直接调用 `stopService`，避免为 STOP 创建未提升的服务实例。
- 保留通知静音、原渠道与通知 ID、canonical 时间锚点及已有计时/结算归属。

修复后的新包重新完整执行 11 项，进程重启和离线冷启动均通过。本轮日志无新增崩溃或 ANR；旧 pid 17045 的崩溃发生在最终测试窗口之前，未混入新版结果。

### 后端缺少 WebSocket 协议实现

初始独立环境仅安装基础 Uvicorn，真实网络请求报 `No supported WebSocket library detected`，虽然 HTTP 与 TestClient 用例正常。已将 `websockets==15.0.1` 加入 `backend/requirements.txt`，在新独立环境安装并通过真实 TCP WS 握手核验。协议文档也补上该运行依赖和部署核验要求。

初始 60 秒夹具还因首次账号缓存清理被替换为默认 25 分钟；该轮在时长断言处中止，结果保留为 [初始夹具失败](physical-initial-fixture-failure.json)。在账号初始化完成后同时更新测试包与测试库配置，再完整复跑；未为通过用例修改产品时长语义。

## 补充验证

| 检查 | 实际结果 |
| --- | --- |
| Android 修复包构建 | PASS，签名与初始验证包相同；正式签名未使用 |
| 原生通知模型 JUnit | 29/29 PASS，0 skipped/failures/errors |
| Flutter 通知静态守卫 | 2/2 PASS |
| 新后端环境专注定向测试 | 25/25 PASS |
| 独立 AppKit 面板运行检查 | 76/76 PASS；使用真实 Flutter 主题快照和 Noto Sans SC，[结果](native-panel/native-smoke.json) |
| Flutter 面板宿主测试 | 7/7 PASS |
| Diff 空白检查 | PASS |

[新版进程日志筛查](fixed-runtime-log-check.json) 对本轮三个测试进程的非空日志执行检查，未匹配 `FATAL EXCEPTION`、`Fatal signal`、`Unhandled Exception`、`RenderFlex overflowed` 或 `Another exception was thrown`。这是限定测试进程和窗口的观察，不代表所有系统日志或所有未来运行情况。

## 正式应用保护与未覆盖范围

正式应用仍为 `com.duoyi.duoyi`，2.0.0 / 142023，安装与更新时间保持原值，APK 哈希保持 `cfcd3d274020287a53118f184165b1e39e9b8a23bbc1976a980faf4cdf849a3b`。未卸载、清数据或读取正式账号私有记录。[保护核验](production-preservation.json)

未执行完整 macOS Flutter 客户端构建/启动：本机缺少完整 Xcode。因此手机 ↔ macOS 原生客户端及自动悬浮窗的完整集成仍未验收；已执行的第二端 Web 同步和独立 AppKit 面板检查分别成立。也未覆盖真实系统休眠/后台唤醒、真实多屏拖动、生产签名覆盖升级或线上部署。

改动仍在 feature 工作区，未提交、推送或发布。测试截图是原生手机实际截屏和真实客户端画面，没有用 HTML 仿制应用。
