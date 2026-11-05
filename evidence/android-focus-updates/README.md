# Android 专注与更新修复验证

分支：`fix/android-focus-updates-notifications`。基线：`4f87864c74702685ab0884999494cffe764f333a`（创建时获取的 `origin/main`）。原五项修复已在 `2dbdfd5` 本地提交，本轮补充深链接修复、通知剩余时间与控制。版本保持 `2.0.0+140023`，未推送、打 tag、发布或部署生产后端。

手机正式版为 `2.0.0 / 142023`，与本地源码及验证包 `2.0.0 / 140023` 是不同产物。设备写入仅限独立包 `com.duoyi.duoyi.focuscheck`；未用低 build 或不同签名覆盖正式应用，未卸载或清除其数据。标准 APK 使用 debug 签名，不能作为正式覆盖升级包。

## 当前 v5 功能

- 通知折叠与展开正文均优先显示 `剩余 24:53`；正计时显示 `已计时 01:23`，暂停冻结并显示“已暂停”。展开第二行保留完整任务名，无任务时显示本地化兜底。
- 运行态提供“暂停 / 重置”，暂停态提供“开始 / 重置”。开始继续原相位、任务与剩余时间，重置回满时长且不增加完成记录，并清理通知与计时前台服务。标准通知按钮点击回到专注页执行。
- 按钮复用既有 Provider 控制入口，校验 session、revision、state，拒绝旧按钮、重复动作和跨会话操作。暂停会话重新加载后恢复暂停通知，可继续同一任务。
- 原生每秒用单调时钟刷新时间，Provider 下发真实计时锚点；切主题、切语言不会重新延长倒计时。保留阶段、主题色、品牌标志、进度和系统 chronometer，不依赖白噪音。
- 保留此前更新判断、真实应用图标、固定选择底栏、无障碍授权识别、严格专注拉回及名称记录、系统后台下载和更新弹窗修复。`duoyi/deep_links` 统一处理 URI，关闭 Flutter 默认命名路由分发，避免严格拉回时重复路由异常。

行为契约见 [Android 专注与应用更新](../../docs/android-focus-updates.md)。需求、设计、中英文 i18n 和未勾选的人工回归项已同步。

## v5 最终自动检查与构建

| 检查 | 实际结果 |
| --- | --- |
| 通知、Provider 生命周期及深链接针对性测试 | 39 通过，0 失败，包含暂停会话重新加载回归 |
| 完整 Flutter 测试 | 2869 通过，0 失败 |
| 原生 `:app:testDebugUnitTest` | 58 通过，0 失败、错误或跳过；含 29 项通知模型测试 |
| `flutter analyze --no-pub` | No issues found |
| 改动 Dart 格式检查 | 11 文件，0 变化 |
| 标准 debug / 独立 ARM64 Profile APK | 均构建成功，exit 0；签名校验成功，合并 MainActivity 的 `flutter_deeplinking_enabled=false` |
| 后端 unittest | 317 通过的既有结果；14 个后端文件逐项哈希未变，本轮未重跑 |

本轮使用 Flutter 3.44.1 / Dart 3.12.1、JDK 17，Android minSdk 24 / compileSdk 36。两份真实 ASCII 副本执行 `pub get --enforce-lockfile`，锁文件保持 `f8d521ef9f8b6a0673d1e8ec51064f71b1a71dcfa8253fe4cee25df6c409db7b`。

[最终检查与产物记录](build-verification-v5.json)、[最终原始日志包](verification-v5-logs.tar.gz)、[隔离源码清单](source-manifest-v5.json)、[标准源码清单](source-manifest-standard-v5.json) 绑定相同的 1268 个原仓库文件哈希，最终仓库与副本复核 0 缺失、0 差异。清单的 `source_head` 是构建时基线 `2dbdfd5`，未提交改动由逐文件哈希绑定；不把基线提交号当成独立产物身份。

首次通知测试因测试辅助函数不接收 null 而编译失败，另有两处多余转义和测试格式问题；均修正后重跑。一次限定范围复审发现暂停恢复标记遗漏及刷新异常后不再调度，两处均修复，并新增暂停恢复回归。中间成功结果和源码变化分别保留在日志包 `initial-v5/`；以上数字仅来自 `v5-final`，不继承中间结果。需求与设计的两处文档补充另有前后哈希记录，未改变编译源码，见 [文档核对记录](physical-xiaomi-20261105T021343Z/spec-sync-v5.json)。

原中文路径曾触发 Flutter LSP 初始化异常及 JNI/CMake 生成输出读取失败；最终分析和构建在真实 ASCII 副本完成。未修改 SDK、全局配置、依赖锁或签名规则来绕过这些问题。旧失败记录保留在历史日志中。

## 当前本地 APK

| 本地产物 | 身份 / 大小 | SHA256 |
| --- | --- | --- |
| [独立验证 Profile APK](../../build/app/outputs/flutter-apk/app-focuscheck-profile.apk) | `com.duoyi.duoyi.focuscheck`，多仪·专注验证，`2.0.0 / 140023`，105,675,533 bytes | `7c902052b53a6782df5e6a999015395d27ced8fd069c106d0696775f8d6d762f` |
| [标准 debug APK](../../build/app/outputs/flutter-apk/app-debug.apk) | `com.duoyi.duoyi`，`2.0.0 / 140023`，160,488,064 bytes | `cecc6f22bb2182c6d4f9f5cb40579a8524d624c85d834ecea7776cc60af52cb9` |

这些 APK 是本地忽略的构建输出，不进入 Git。两份 v4 复核 APK 已按原哈希备份到会话 scratch，当前路径已替换为 v5。见 [验证包复制记录](physical-xiaomi-20261105T021343Z/candidate-v5-review-copy.json) 和 [标准包复制记录](physical-xiaomi-20261105T021343Z/standard-v5-review-copy.json)。

标准副本无身份修改并使用公共配置；隔离副本只修改 applicationId、显示名和外部 URI scheme，初始后端为本机夹具。两包的 namespace / Activity 仍为 `com.duoyi.duoyi.MainActivity`，使用同一 debug 证书。Profile 为 ARM64 AOT，debug 为 ARM64 JIT；`armeabi-v7a`、`x86_64` 的插件库目录不能证明其他 Flutter 运行架构已验证。标准包未安装到手机正式应用。

## v5 真机专项：因 USB 断连未执行

目标为小米 `24129PN74C`、serial `2df52c4c`，Android 16 / API 36、ARM64、1200×2670、520dpi、系统字号 1.25。设备代理在 host UTC `2026-11-05T04:33:28Z` 确认目标已从 ADB 及主机 USB 清单消失，约 45 秒内多次检查均无设备。

[v5 专项报告](physical-xiaomi-20261105T021343Z/v5-notification/manual-v5-notification-results.json) 的结果为 **NOT_RUN_DEVICE_DISCONNECTED**：安装哈希绑定、可见剩余时间递减、实际暂停按钮、实际开始/重置按钮、实际通知正文点击这五项均未执行，0 项通过、0 项产品失败。本轮没有安装、UI、设置或进程操作，也没有新增 v5 手机截图。自动检查与配置好的 PendingIntent 不作为真实点击证据。

继续验收需要重新连接同一手机并保持 USB 调试授权，再仅对独立验证包 `install -r`，用新鲜卡片截图定位后实际点击。手机上最后可信的验证包仍是 v4；当前手机状态在断连后无法重新核实。

## 已完成的小米历史实测

见 [本轮手机基线](physical-xiaomi-20261105T021343Z/baseline.json)、[v3 首轮真机报告](physical-xiaomi-20261105T021343Z/manual-physical-results.json)、[v4 路由补测报告](physical-xiaomi-20261105T021343Z/v4-recheck/manual-v4-recheck-results.json)。

| 项目 | 已有真机结论及边界 |
| --- | --- |
| 同版本更新误报 | 旧接口 `2.0.0 / 200000` 显示已是最新版本 |
| 图标与应用选择 | 扫描 205 个应用，真实图标/名称/包名可见，取消/保存和固定底栏可用；搜索输入未验证 |
| 无障碍识别 | 经真实系统 UI 授权后立即识别，22 秒以上轮询保持；未授予 UsageStats，正式服务条目保留 |
| 严格专注 | v4 实际打开 AI 扫描被拉回，记录 `AI扫描 (com.xiaomi.scanner)`；明确暂停、重置或关闭后不再拉回 |
| 路由修复 | v3 的 `_onUnknownRoute` 空值异常在 v4 同路径中计数 0；热链接与 Activity 重建入口通过，真正进程冷启动未验证 |
| 旧计时通知 | 主题色、进度递增、暂停冻结、继续和重置清理通过；实际通知正文点击在小米上仍未执行 |
| 后台下载 | 关闭弹窗 / Home 后系统进度到 69%，随后完成；完成通知点击、普通进程退出续传、失败/取消/重试未验证 |

主会话已查看 [v4 紧凑通知裁图](../screenshots/android-focus-updates/physical-xiaomi-20261105T021343Z/v4-recheck/03-focus-notification-card-crop.png)：只有“专注中 / 无关联任务”和进度，促成本次 v5 时间与控制增强。该旧图不代表新通知外观。全部公开真机图已裁去无关状态栏或只保留本应用卡片，整屏私密通知只在会话 scratch。

v4 最后观察到计时 25:00、严格/监控关闭、`951101` 与计时前台服务消失，正式包版本、安装时间和 APK 哈希及显示设置未变，独立包与授权保留。v5 没有设备写入；未把该旧状态冒充断连后的重新核验。

## 历史模拟器与构建证据

- [v1 自动检查](build-verification.json)、[v1 日志](verification-logs.tar.gz)、[首轮设备报告](e2e-run/manual-e2e-results.json)：图标与授权识别；旧选择器滚动问题触发固定底栏修复。
- [v2 自动检查](build-verification-v2.json)、[v2 日志](verification-v2-logs.tar.gz)、[v2 核心报告](e2e-v2/manual-e2e-v2-results.json)、[v2 补测](e2e-v2-followup/manual-followup-results.json)：Chrome 拉回与名称记录、固定底栏、暂停不拦截、实际通知正文点击、legacy 同版本不误报。补测发现更新弹窗空白，随后修复。
- [v3 自动检查](build-verification-v3.json)、[v3 日志](verification-v3-logs.tar.gz)、[v3 门禁](delivery-gate-v3.json)：更新弹窗 widget 回归通过。保留 [debug 设备失败](e2e-v3/manual-download-results.json) 和 [原始采集](e2e-v3/initial-debug-device-attempt.tar.gz)。
- Profile 首次因系统服务缺失 [未执行](e2e-v3-profile/manual-profile-download-results.json)；保留 AVD 后完成 [恢复](e2e-v3-recovered/coldboot-recovery.json) 和 [下载闭环](e2e-v3-recovered/manual-profile-download-results.json)：系统进度 4%→10%→26%，重入 47%/48%，完成通知实际点击进入未知来源授权页，开关保持 OFF、未安装载荷。
- [v4 自动检查](build-verification-v4.json)、[v4 日志](verification-v4-logs.tar.gz)、[构建后文档差异](post-build-documentation-v4.json) 保留其 1267 文件快照和 2849 Flutter / 42 native 通过结果，仅作历史记录，不代替 v5。

旧模拟器 debug 启动/输入 ANR 根因未定位，见 [ANR 原文](e2e-v2/am_anr-events.txt)；系统恢复和 Profile 无 ANR 不证明 debug 问题已解决。夹具元数据为 `2.0.1`，实际载荷为 `2.0.0`，只验证传输与入口，不是生产升级。

## 收尾与剩余边界

本轮 fixture / 截图 viewer 已按准确命令行关闭，端口 18763 / 18764 均不再监听，见 [清理记录](physical-xiaomi-20261105T021343Z/host-cleanup.json)。此前私密 viewer 也已关闭。手机缺失，USB reverse 映射状态无法核实；未重启 ADB 或移除其他映射。

待设备恢复后执行 v5 实际通知验收；另有真正进程冷启动、长期锁屏/深度省电、搜索输入、下载进程退出续传与失败/取消/重试、旧 debug ANR、发布签名及正式覆盖升级等待验证。未执行生产部署或完整跨平台发布，本地提交不声称发布验收通过。

四份原始 logcat 因保留尾随空格改用 gzip 存储，解压字节与原文完全一致；当前报告引用已指向 `.txt.gz`。历史 v4 索引保留原文哈希，最终 v5 索引记录压缩文件哈希，见 [原始日志存储记录](physical-xiaomi-20261105T021343Z/raw-log-storage-v5.json)。

[v5 本地提交门禁](delivery-gate-v5.json) 结论为 `local_commit_ready=true`、`product_device_acceptance=false`：代码与证据可保存为本地提交，手机重连后的实际通知验收仍待执行。
