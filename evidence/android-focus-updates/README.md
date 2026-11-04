# Android 专注与更新修复验证

分支：`fix/android-focus-updates-notifications`。基线：`4f87864c74702685ab0884999494cffe764f333a`（创建时获取的 `origin/main`）。本轮交付本地修复分支，版本保持 `2.0.0+140023`，未推送、发布、打 tag 或部署生产后端。

修复前手机实装 `2.0.0 / 142023`，本分支源码与验证包为 `2.0.0 / 140023`，两者是不同构建产物。设备验证只操作独立包 `com.duoyi.duoyi.focuscheck`，未用低 build 或不同签名覆盖手机正式应用，未卸载或清除其数据。标准 APK 为 debug 签名，不是正式覆盖升级包。

## 实现范围

1. 更新判断优先比较语义版本，同名版本只接受可信真实 build；兼容旧服务器错误推算的 `2.0.0 / 200000`。
2. 分心应用选择器展示原生图标、名称、包名。内容独立滚动，底部“取消 / 完成”固定可见，保留搜索与黑白名单草稿规则。
3. 无障碍短名/完整组件名等价识别，轮询保留授权字段，打开面板和返回前台重新读取授权状态。
4. 严格专注拉回带会话期限和有限重试；记录保存应用名称与包名，防止旧异步结果或原生事件跨会话回放。
5. 独立计时通知显示阶段、关联任务、系统计时器与进度，沿用主题强调色；DownloadManager 负责后台 APK 下载、进度通知和完成后的安装入口。更新弹窗兼容长说明和长安装包名。

行为契约见 [Android 专注与应用更新](../../docs/android-focus-updates.md)。

## 最终自动检查与构建（v3）

| 检查 | 结果 |
| --- | --- |
| 完整 Flutter 测试 | 2845 通过，0 失败 |
| 个人页完整 widget 测试 | 45 通过，包含两条更新弹窗长说明回归 |
| 选择器完整 widget 测试 | v2 时 12 通过；v3 完整套件再次覆盖 |
| 后端 unittest | 317 通过，0 失败 |
| 原生 `:app:testDebugUnitTest` | 42 通过，0 失败、错误或跳过 |
| ASCII 实体副本 `flutter analyze --no-pub` | No issues found |
| 标准调试 APK / 隔离调试 APK | 均构建成功，exit 0 |

后端与原生测试在布局补丁前通过。已逐文件核对 209 个 `backend/` 与 `android/` 文件哈希未变，因此没有为两次 Flutter 布局修复重复运行这两组。v3 相比 v2 只改变 `lib/screens/mine_screen.dart`、`test/screens/today_mine_smoke_test.dart` 和行为文档；共享弹窗组件未修改。

工具链：Flutter 3.44.1 / Dart 3.12.1、JDK 17、Python 3.12.14；Android minSdk 24 / targetSdk 36。两份副本执行 `pub get --enforce-lockfile` 均成功，锁文件与原仓库逐字节一致，SHA256 为 `f8d521ef9f8b6a0673d1e8ec51064f71b1a71dcfa8253fe4cee25df6c409db7b`。

原中文路径的 Flutter 分析器曾在 LSP 初始化时崩溃，正式分析在真实 ASCII 副本执行；原工作区 `dart analyze` 在前一轮另行通过。v3 原路径标准构建另因 JNI/CMake 生成输出的 MD5 读取失败而 exit 1，失败日志保留；随后在同源、无身份修改的全新 ASCII 标准副本构建成功（Gradle 42.1 秒），哈希核对后复制回工作区。未修改 SDK、全局配置、产品源码或依赖以绕过这些问题。

最新结果：[build-verification-v3.json](build-verification-v3.json)、[原始日志包](verification-v3-logs.tar.gz)。日志保留夹具失败、真实 `LayoutBuilder` 固有尺寸异常、后续滚动条缺控制器异常与最终 GREEN，分别注明诊断意义；不把所有早期失败算成同一产品问题。最终两个新场景均实际滚动 40 行更新说明，在 390px 普通屏与 320px / 1.5 倍文字下显示长安装包名并关闭弹窗。

[v3 本地提交门禁](delivery-gate-v3.json) 已通过，0 条硬阻塞；此结论不等于设备或发布验收通过。

## 当前源码和 APK

[隔离副本源码清单](source-manifest-v3.json) SHA256：`8b127c56b35002a1f76d208bb9b960640e9fa5b0d2ca3b3be7bc4665e98de6e5`。[标准副本源码清单](source-manifest-standard-v3.json) SHA256：`67664503f2403bc24c2c9a1113992b89c3038c3c920c5c4ba2176842da7a83cd`。

两份清单包含相同的 1266 个原仓库文件哈希，构建后复核原仓库 0 缺失、0 差异。清单的 `source_head` 是构建时基线，候选实现由逐文件哈希绑定；后续本地提交、证据和文档补充不改变被测产品源码。

| 产物 | 身份 / 大小 | SHA256 |
| --- | --- | --- |
| [标准调试 APK](../../build/app/outputs/flutter-apk/app-debug.apk) | `com.duoyi.duoyi`，`2.0.0 / 140023`，160,480,812 bytes | `ef3aa5b6347a225b33512fe3ac4d523dfdd885cd7ad607e32758956c7b5ae7d2` |
| 隔离调试 APK（会话 scratch 的 `android-candidate-v3/build/app/outputs/flutter-apk/app-debug.apk`） | `com.duoyi.duoyi.focuscheck`，`2.0.0 / 140023`，160,480,428 bytes | `07ea1fb5cc07dccbc44601d923d698f66b7154e0d39289ade963cabde32eb825` |
| 隔离 Profile APK（会话 scratch 的 `android-candidate-v3/build/app/outputs/flutter-apk/app-profile.apk`） | `com.duoyi.duoyi.focuscheck`，`2.0.0 / 140023`，105,609,957 bytes，AOT Profile | `dc20a1644f0f7bb4ff82eeb46104570f414d22e3179e3260d11327ba4bd8e412` |

标准副本没有身份修改，使用仓库公共配置。隔离副本只修改 applicationId、显示名和外部 URI scheme，初始后端为本机下载夹具；native namespace / Activity 仍为 `com.duoyi.duoyi.MainActivity`。三份 APK 均使用 debug 证书；aapt 实际报告均包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 目录，但本轮 Flutter 引擎 / Profile AOT 载荷为 ARM64，不能据插件 ABI 目录宣称其他架构已经验证。

## 设备证据及版本边界

测试设备为 API 35 ARM64 官方模拟器 `duoyi_api35_arm64` / `emulator-5554`，保留 AVD 数据，使用独立验证包。

- v1 隔离 APK `d7e12c65…9379b`：真实应用图标、名称、包名可见；无障碍绑定后经过 20 秒轮询仍显示授权。见 [首轮报告](e2e-run/manual-e2e-results.json) 和 [图标原图](../screenshots/android-focus-updates/main-inspection/picker1.png)。旧选择器需要滚到全名单末尾才能保存的观察触发固定底栏修复；三条长名单回归在旧布局 RED 后通过。
- v2 隔离 APK `3e1a8481…c458d0`：固定“取消 / 完成”可见，Chrome 名单保存为 `Blacklist · Selected 1`；严格专注运行时实际启动 Chrome 被拉回专注页，原生日志三次记录拉回；惩罚显示 `Chrome (com.android.chrome)`。仅授予无障碍，未授予使用情况访问。见 [v2 核心报告](e2e-v2/manual-e2e-v2-results.json) 与 [固定底栏原图](../screenshots/android-focus-updates/e2e-v2/01-picker-fixed-done-and-cancel.png)。
- 同一 v2 APK：通知 ID `951101`、channel `duoyi_focus_timer_v1` 与系统 chronometer 正确；15 秒内进度 10/1000 → 20/1000；暂停后 `24:07` / 进度 35 十秒不变，继续后恢复；通知栏实际显示 `Focus · 23:39` 和进度条，沿用红色主题强调色。重置清理通知和服务。主会话已查看 [通知原图](../screenshots/android-focus-updates/main-inspection/v2-focus-notification.png)。
- [v2 补测报告](e2e-v2-followup/manual-followup-results.json)：确认通知 Paused 后启动 Chrome，Chrome 保持前台、拉回次数 0；实际点击通知正文返回专注页；旧接口 `2.0.0 / 200000` 显示 `You are up to date`。28 份补测文件哈希已全部核对一致。
- v2 补测还真实发现“有更新”分支只有遮罩、没有弹窗卡片，见 [失败原图](../screenshots/android-focus-updates/e2e-v2-followup/c3b-update-dialog-blank.png)。这触发本轮 v3 的固有尺寸与滚动修复，最终 widget 回归已通过；不把 v2 未运行的后台下载记为通过。

v3 调试包已实际显示完整更新弹窗，安装包名和“关闭 / 下载并安装”均可见。主会话已查看 [更新弹窗原图](../screenshots/android-focus-updates/main-inspection/v3-update-dialog.png)，并独立核对模拟器安装 APK 的哈希等于 v3 候选。详见 [调试包阶段报告](e2e-v3/manual-download-results.json)。这轮再次遇到 ANR，多份后续状态采集为空；超过 25 分钟后停止并保存 [原始现场](e2e-v3/initial-debug-device-attempt.tar.gz)，后台下载、进程退出后继续和完成安装入口均未记为通过。

同源 AOT Profile 包使用与隔离调试包相同的 debug 证书。首次尝试因模拟器 `package/activity/window/dropbox` 服务缺失、`system_server` 重启而根本未安装，见 [未执行报告](e2e-v3-profile/manual-profile-download-results.json)。主会话保留 AVD 磁盘数据，以 SwiftShader 无窗口模式冷启动，确认系统服务恢复，见 [恢复记录](e2e-v3-recovered/coldboot-recovery.json)。这次环境恢复不证明先前 ANR 的根因。

恢复后在独立验证包上实际完成 Profile 下载闭环，见 [最终下载报告](e2e-v3-recovered/manual-profile-download-results.json)：

- 实装 APK 哈希与 Profile 候选一致，首次安装时间保留；启动及本轮交互没有 ANR。
- 真实点击下载后，关闭弹窗并回到桌面，系统 DownloadManager 进度 4% → 10% → 26%，两次真实递增。
- 重入弹窗恢复同一下载，XML 为 47%、随后截图为 48%，没有创建第二条下载。主会话已查看 [恢复进度原图](../screenshots/android-focus-updates/e2e-v3-recovered/09-dialog-restored.png)。
- 完成后出现应用通知 ID `7307`，点击正文进入 Android“安装未知应用”授权页，未切换开关、未安装载荷；返回后按钮显示“安装已下载的安装包”，下载已完成。主会话已查看 [授权入口原图](../screenshots/android-focus-updates/e2e-v3-recovered/11-after-notif-tap.png)。

普通进程退出后的续传未验证；失败、取消和重试的设备交互未执行。Profile 与原调试包结果分别记录，Profile 本轮通过不代表调试包的启动 / 输入 ANR 已修复。

v2 首次安装及预热期间记录四条 ANR：两条启动未完成、一条无障碍服务执行超时（83394ms）、一条输入分发超时，见 [事件原文](e2e-v2/am_anr-events.txt)。后续进程重启后完成了上述核心用例，但 ANR 根因未定位。现有证据没有定位实际阻塞点的应用主线程栈，不能认定服务内部阻塞或仅为环境原因。核心报告中的早期过强归因已校正，原始日志保留；[启动页原图](../screenshots/android-focus-updates/main-inspection/v2-anr-dialog.png) 未显示 ANR 对话框。

下载夹具发布元数据为 `2.0.1`，实际传输 APK 仍为 `2.0.0`，仅验证传输、状态恢复和安装入口，不是生产版本升级。夹具仅绑定本机地址，不涉及真实账号或生产服务。

## 仍需验证

- 小米 `24129PN74C` / Android 16 的授权返回、实际拉回、通知和省电行为：设备已从 ADB 断开，修复前观察见 [baseline.json](baseline.json)。
- 普通进程退出后的下载续传，以及失败、取消、重试的设备交互；调试包重复 ANR 的根因仍待定位。
- 发布签名、正式覆盖升级、完整跨平台发布门禁与生产后端部署。

历史证据保留在 [v1 自动检查](build-verification.json)、[v1 日志](verification-logs.tar.gz)、[v2 自动检查](build-verification-v2.json)、[v2 日志](verification-v2-logs.tar.gz) 和 [初始设备失败采集](initial-device-attempt.tar.gz)。旧标准 APK 路径已被当前 v3 产物替换，v2 标准 APK 已备份到会话 scratch；当前产物以上表与 v3 元数据为准。
