# Android 专注与更新修复验证

分支：`fix/android-focus-updates-notifications`。基线：`4f87864c74702685ab0884999494cffe764f333a`（创建时获取的 `origin/main`）。原五项修复已在 `2dbdfd5` 本地提交，深链接与通知修复已在 `cdee4e4` 本地提交；本轮修复白名单模式下分心应用拉回失败。版本保持 `2.0.0+140023`，未推送、打 tag、发布或部署生产后端。

手机正式版为 `2.0.0 / 142023`，与本地源码及验证包 `2.0.0 / 140023` 是不同产物。设备写入仅限独立包 `com.duoyi.duoyi.focuscheck`；未用低 build 或不同签名覆盖正式应用，未卸载或清除其数据。标准 APK 使用 debug 签名，不能作为正式覆盖升级包。

## 当前 v10：支付宝与暂停后继续真机通过

前次未验收检查点已保存为 `5473be8`。本次在同一小米设备、白名单仅 QQ/微信的独立验证包上完成所要求的两项修复验收，**以用户将该包省电策略设为“无限制”为必要条件**，不表示能绕过系统冻结或覆盖所有设备/长期省电场景。

- [直接内核证据与用户设置记录](whitelist-v10/kernel-freeze-and-authorization.json)：失败时 ActivityManager 显示 `isFrozen=false`，但实际 `/sys/fs/cgroup/apps/uid_10565/pid_11828/cgroup.freeze=1`、`cgroup.events` 为 `frozen 1`，主线程运行计数不变，通知冻结在22:00。因此不能仅凭服务绑定和 ActivityManager 标志认定后台仍执行。
- [同 APK 省电策略对照](whitelist-v10/battery-unrestricted.json)：不换 APK，用户通过真实系统 UI 将验证包设为无限制后，内核持续 `frozen 0`、计时递减；支付宝首次、重开、QQ后台停留后再开及微博全部在 +2s/+5s 返回多仪，QQ/微信放行。此前 [冻结时失败](whitelist-v10/active-first.json) 仍完整保留。
- [暂停验收](whitelist-v10/paused.json)：真实按钮暂停后原生拦截停用，支付宝在 +2s/+5s 保持前台，没有拉回请求。
- [继续验收](whitelist-v10/resumed.json)：真实按钮继续同一会话，session ID 不变、revision 2→3，恢复暂停剩余时间而非新建25分钟；支付宝首次/重开/QQ停留后再开和微博均拉回，QQ放行，通知持续递减且内核未冻结。
- 代码修复另消除同步主线程系统查询风险：`getStatus/getForegroundApp` 使用独立后台快照、单查询合并、最多32等待者、销毁结束等待和丢弃迟到结果。它不改变名单语义、不以记录快照作为拉回依据；不能把省电对照的效果单独归因于这项代码改动。

[v10 构建与来源](whitelist-v10/build.json)、[原始检查日志](whitelist-v10/checks-logs.tar.gz)：本次相关 Flutter **41通过**、原生 **100通过**（新增异步查询10项）、独立 Profile 构建及验签通过。1274项源码绑定，未重跑全量 Flutter/analyze/backend/标准 debug。构建后只补充了省电冻结文档，执行源码未变，差异已明确记录。旧 v9 两份通用输出仍保留，最新独立包另存为 [v10 验证 APK](../../build/app/outputs/flutter-apk/app-focuscheck-v10-profile.apk)，SHA256 `f9c71d0820b7f091b4f91fd10ceecda1258aabc83b6ddbd121af99b5db1eb8a9`，105,708,301字节；这不是正式签名覆盖升级包。

[最终收尾](whitelist-v10/cleanup.json)：用户重置本次测试并关闭严格/监控后，读回无运行快照、原生OFF、951101和计时FGS均为0；QQ/微信白名单完整保留，已授权许可和省电无限制保留。正式包/布局包版本和安装时间未变。旧通知动作行可达性不在本次验收范围内，仍是独立未完成项。

## 历史 v9 白名单检查点（当时真机未验收）

[原小米复现](physical-xiaomi-20261105T021343Z/whitelist-repro-20261105T061121Z/manual-whitelist-repro.json) 确认微博已命中原生拦截集合，但旧日志记为“已拉回”后，实际前台仍是微博。复现时的原生集合实际有 202 项，微博、支付宝在集合内，QQ、微信不在；曾把 XML `<set>` 的空文本误读成空集合，已按子 `<string>` 纠正并保留原始派生记录，不再把名单同步错误当作根因。

- 固定全局 1.5 秒冷却，被拒窗口事件不再推进已接受时刻；不同分心应用共用截止时间，连续事件不再饿死后续拉回。
- 窗口事件触发后约 600ms 验证，只有仍停在同一受拦截应用且配置有效时补发一次。`startActivity` 返回只记 `requested`，观察到多仪真正成为前台才记 `confirmed`。
- 未确认只结束本轮验证，保留真实窗口事件已排队的冷却复查；QQ、微信等允许应用、本应用、配置失效和服务销毁会清空待执行返回，并记录窗口与取消原因。复查不自行排下一轮。
- 已授权使用情况访问时，通过工作线程约每 500ms 查询当前监控起点后、最近 5 秒的 `UsageEvents`，仅使用包名、类型、时间补漏。使用情况触发每轮只请求一次，冷却中重新查询当前切换，不依据旧缓存排队；未授权不读取，锁屏不查询或拉起。
- 纯 Kotlin 回归覆盖固定冷却、旧窗口、明确离开、在途查询代次、真实事件年龄和每轮请求上限。未新增 Manifest 权限声明或读取窗口内容；系统权限均由用户通过真实 UI 决定。
- 完全相同的启停状态、包集合和到期时间不再重发原生配置变更，避免恢复前台时取消待验证返回或移动监控起点。v8 的临时查询摘要已从最终 v9 源码和 DEX 中移除。

### v9 自动检查与构建

本次 v9 实际执行：两文件静态契约 **5 通过**、原生 **90 通过，0 失败、错误或跳过**，标准 debug 与独立 Profile APK 构建、验签均成功。v9 与 v7 的源码差异仅为原生服务和本页行为契约文档 `docs/android-focus-updates.md`；790 个 Flutter、测试、资源及配置输入逐文件相同，因此明确沿用 v7 的七文件定向 **55 通过**、完整 Flutter **2871 通过**、分析无问题、7 文件格式 0 变化，本次没有重跑这些检查。14 个后端文件未变，317 项既有结果未重跑。

[v9 检查与构建](build-verification-whitelist-v9-final.json)、[v9 日志包](verification-whitelist-v9-final-logs.tar.gz)、[v9 隔离清单](source-manifest-whitelist-v9-final.json)、[v9 标准清单](source-manifest-standard-whitelist-v9-final.json) 绑定相同的 1272 个源文件，标准副本无身份差异，候选仅三项，前后源/锁无漂移。`source_head=cdee4e4` 仅是构建基线，实际 WIP 由逐文件哈希绑定。日志包含本次真实 JUnit XML、Flutter 输入复用证明，以及归档脚本首次摘要字段不匹配的失败记录与修正说明。v6 的旧文字守卫失败、v7 全套通过和 v6 原生结果沿用来源仍保留于 [v7 检查](build-verification-whitelist-v7-final.json) 与 [v7 日志包](verification-whitelist-v7-final-logs.tar.gz)，不覆盖历史。

[v7 真机报告](physical-xiaomi-20261105T021343Z/whitelist-v7-final-20261105T100507Z/manual-whitelist-results.json) 中，微博首次、重开、QQ/微信放行、允许应用快切和暂停/重置释放通过；支付宝首次、重开、600ms 跨包场景仍失败，暂停后继续还出现服务重连后的不拦截。使用情况访问已通过真实 UI 开启并保留，后台弹出许可也保留，不能再以尚未授权解释失败。[v8 诊断构建](build-verification-whitelist-v8-diagnostic.json) 与 [受限实机诊断](physical-xiaomi-20261105T021343Z/whitelist-v8-diagnostic-20261105T115617Z/diagnostic.json) 单独保留：名单未按要求恢复，两次 +5s 与下一步动作重叠，故不作为稳定拉回验收；约 23 秒后的支付宝请求/桌面取消也不能解释最初失败。v8 运行期间未用 UIAutomator 时未出现服务销毁，但因果机制未证实。[本应用裁图及视觉核对](physical-xiaomi-20261105T021343Z/whitelist-v7-final-20261105T100507Z/screenshot-review.json) 仅证明可见页面状态。[文档核对](physical-xiaomi-20261105T021343Z/spec-sync-whitelist-v6.json) 的两处需求/设计漂移已补齐。

[受控复测](physical-xiaomi-20261105T021343Z/whitelist-v8-controlled-20261105T121653Z/controlled-setup-blocked.json) 在恢复 QQ/微信白名单的真实 UI 操作上阻塞，A/B/B2/C/D 全部未执行，没有新增产品通过结论。后续主会话也未解决该输入操作，已停止重复试验。支付宝稳定拉回与暂停后继续仍未验收，`product_device_acceptance=false`。设备仍为 v8，最终 v9 仅完成源码检查与构建，未安装实测；不能把两者混为同一产物。

[最终手机收尾](physical-xiaomi-20261105T021343Z/main-cleanup-whitelist.json)：验证包严格专注/监控关闭、无运行测试计时、`951101` 和计时前台服务清理，手机回桌面；验证包白名单仍为空，未声称恢复成功。正式包与布局包未覆盖、未清数据、未修改其偏好或权限。

### 历史 v2 检查与真机失败

历史 v2 实测：六文件 Flutter 定向 53 通过、完整 Flutter 2870 通过、原生 77 通过；[v2 检查](build-verification-whitelist.json)、[v2 日志](verification-whitelist-logs.tar.gz)、[v2 隔离清单](source-manifest-whitelist.json)、[v2 标准清单](source-manifest-standard-whitelist.json) 保留各自 1270 文件身份，不能替代当前 v9。

[白名单 v2 真机报告](physical-xiaomi-20261105T021343Z/whitelist-v2-recheck-20261105T071213Z/manual-whitelist-results.json) 当时为 **5 项通过、3 项失败，持续拉回未验收通过**。设备 `base.apk` 与 v2 哈希一致；真实 UI 保存白名单仅 QQ、微信，原生补集 203 项正确。首次微博默认启动后实际返回并在 2s/5s 保持，但微博已有任务重复打开、600ms 跨包打开支付宝、支付宝从桌面启动均未稳定拉回；该失败历史保留，后续定位与修复另记。

QQ/微信放行及分心→允许应用快切不被旧任务抢回，暂停/重置释放均通过。该轮收尾为“已暂停 25:00”、严格/监控关闭、白名单两项保留，`951101` 与计时前台服务均为 0，正式包、布局包、授权和设备设置保留。日志实际按 PID 29386 过滤，原 `own_uid` 字段已纠正，不声称覆盖全 UID/系统日志。后续服务/进程短诊断单独记录，不能沿用此前锁屏阻塞或该轮空闲状态。

公开 [本应用裁图](../screenshots/android-focus-updates/physical-xiaomi-20261105T021343Z/whitelist-v2-recheck-20261105T071213Z/01-focus-page-idle-strict-off-cropped.png) 仅用于页面/隐私核对，不证明拉回成功；首次误拍的第三方界面已由设备任务删除，未入库。此前 v5 通知操作行不可达仍是独立未修项。

## 小米权限与支付宝事件定位

[只读系统证据](physical-xiaomi-20261105T021343Z/whitelist-miui-permissions-readonly-20261105T075439Z/miui-permissions-readonly.json) 记录到小米 `ActivityStarterImpl: MIUILOG- Permission Denied Activity`，两次拒绝均对应验证包返回请求；真实系统 UI 的“后台弹出界面”为拒绝。辅助功能已连接不代表系统允许从后台显示。

用户已明确授权仅为“多仪·专注验证”开启这一项。[同 APK 授权对照](physical-xiaomi-20261105T021343Z/whitelist-v3-miui-authorized-20261105T080220Z/manual-whitelist-results.json) 全程保留 v3 诊断包 `6c88b84a…72726`，通过真实系统 UI 将该项改为“始终允许”，测试后保留允许，正式包及其他权限未改。授权前后为不同测试会话，白名单和严格配置相同；微博首次与已有任务重开均在 +2s/+5s 保持多仪前台，QQ/微信与快切放行通过。

该次 v3 授权对照中，支付宝仍停留其登录 Activity，自有服务未收到它的窗口事件，也未发出拉回请求。该结果只证明后台显示许可没有解决支付宝路径，不能把微博通过推广为全部分心应用已验收。公开 [完整服务时间线](physical-xiaomi-20261105T021343Z/whitelist-v3-miui-authorized-20261105T080220Z/own-service-timeline.txt) 已从原始日志恢复两处截短数值，保留原派生记录哈希。

[四类事件实机诊断](physical-xiaomi-20261105T021343Z/whitelist-v5-events-only-20261105T083023Z/diagnostic.json) 使用 `51b8c620…b4620`，实际已连接服务订阅 8/32/2048/4194304 四类事件：微博正常到达，支付宝首次和重开仍为四类各 0 次、实际前台仍是其登录 Activity。诊断包仅增加日志订阅，未读取窗口内容或改变拉回行为。[诊断构建记录](build-verification-whitelist-v5-events-only.json) 明确保留生成器引号转义差异；该诊断用于定位输入缺失，不能替代当前 v9 的源码和实际设备结论。

## 历史 v5 功能

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

## 历史 v9 本地 APK（当前 v10 见顶部）

| 本地产物 | 身份 / 大小 | SHA256 |
| --- | --- | --- |
| [独立验证 Profile APK](../../build/app/outputs/flutter-apk/app-focuscheck-profile.apk) | `com.duoyi.duoyi.focuscheck`，多仪·专注验证，`2.0.0 / 140023`，105,691,917 bytes | `8e0ee421b64675f9f92f442e8c54b03fe81dc7190357cb11c7db1f62134aa117` |
| [标准 debug APK](../../build/app/outputs/flutter-apk/app-debug.apk) | `com.duoyi.duoyi`，`2.0.0 / 140023`，160,509,744 bytes | `3976bcdd35dd9e3be4c96c28868bac97d82a4a1d470395c6629a5ff1f7a2dc7f` |

这些 APK 是本地忽略的构建输出，不进入 Git。旧 v5、白名单 v2、v7 两包均已分别按原哈希备份到会话 scratch，当前路径是 v9。见 [v9 验证包复制记录](physical-xiaomi-20261105T021343Z/candidate-whitelist-v9-review-copy.json) 和 [v9 标准包复制记录](physical-xiaomi-20261105T021343Z/standard-whitelist-v9-review-copy.json)。旧检查及真机报告继续保留各自产物身份；v8 诊断包仅在 scratch 中留存。

标准副本无身份修改并使用公共配置；隔离副本只修改 applicationId、显示名和外部 URI scheme，初始后端 define 为 `http://127.0.0.1:18763`，本轮未启动该后端。两包 namespace / Activity 仍为 `com.duoyi.duoyi.MainActivity`，使用同一 debug 证书。Profile 为 ARM64 AOT，debug 为 ARM64 JIT；`armeabi-v7a`、`x86_64` 的插件库目录不能证明其他 Flutter 运行架构已验证。标准包未安装到手机正式应用。

## v5 真机专项：已重连实测，通知操作未验收通过

目标为小米 `24129PN74C`、serial `2df52c4c`，Android 16 / API 36、ARM64、1200×2670、520dpi、系统字号 1.25。本次在 host UTC `2026-11-05T05:23:46Z` 开始补测，已 `install -r` 安装最终 v5 独立验证包，设备 `base.apk` 哈希与 `7c902052…d762f` 完全一致，首次安装时间保留。

[本次实机报告](physical-xiaomi-20261105T021343Z/v5-device-retry-20261105T052346Z/manual-v5-notification-results.json) 结果为 **PARTIAL_PASS：3 项通过，2 项阻塞**。安装绑定、剩余时间递减（`24:19→23:57`，后续到 `20:58`）、真实点击通知正文返回专注页通过，相关路由异常计数 0。但本次通知卡片始终收起，多次展开尝试均未显示操作行，因此通知上的暂停、开始和重置未能实际点击，不能记为通过。主会话已视觉核对 [完整卡片裁图](../screenshots/android-focus-updates/physical-xiaomi-20261105T021343Z/v5-device-retry-20261105T052346Z/02-focus-notification-remaining-23m40.png)；系统记录 `actions=2` 不等于动作可达。

该次 v5 通知补测收尾时，手机在应用内重置到 25:00，`951101` 与计时前台服务消失，严格/监控关闭；正式包和既有布局验证包版本、安装时间与正式 APK 哈希未变。本次未改全局显示设置、未启动本机服务、未新增或删除 reverse 映射。这是 v5 通知补测结束时的状态；后续白名单问题的会话与设备状态见上方新报告，不能沿用该空闲状态。上一轮 [USB 断连未执行报告](physical-xiaomi-20261105T021343Z/v5-notification/manual-v5-notification-results.json) 作为历史保留，通知动作仍需解决卡片可达性后补测。

## 已完成的小米历史实测

见 [本轮手机基线](physical-xiaomi-20261105T021343Z/baseline.json)、[v3 首轮真机报告](physical-xiaomi-20261105T021343Z/manual-physical-results.json)、[v4 路由补测报告](physical-xiaomi-20261105T021343Z/v4-recheck/manual-v4-recheck-results.json)。

| 项目 | 已有真机结论及边界 |
| --- | --- |
| 同版本更新误报 | 旧接口 `2.0.0 / 200000` 显示已是最新版本 |
| 图标与应用选择 | 扫描 205 个应用，真实图标/名称/包名可见，取消/保存和固定底栏可用；搜索输入未验证 |
| 无障碍识别 | 经真实系统 UI 授权后立即识别，22 秒以上轮询保持；未授予 UsageStats，正式服务条目保留 |
| 严格专注 | v4 实际打开 AI 扫描被拉回，记录 `AI扫描 (com.xiaomi.scanner)`；明确暂停、重置或关闭后不再拉回 |
| 路由修复 | v3 的 `_onUnknownRoute` 空值异常在 v4 同路径中计数 0；热链接与 Activity 重建入口通过，真正进程冷启动未验证 |
| 旧计时通知 | 主题色、进度递增、暂停冻结、继续和重置清理通过；v4 当时未执行正文实际点击，v5 重连补测已通过正文点击 |
| 后台下载 | 关闭弹窗 / Home 后系统进度到 69%，随后完成；完成通知点击、普通进程退出续传、失败/取消/重试未验证 |

主会话已查看 [v4 紧凑通知裁图](../screenshots/android-focus-updates/physical-xiaomi-20261105T021343Z/v4-recheck/03-focus-notification-card-crop.png)：只有“专注中 / 无关联任务”和进度，促成本次 v5 时间与控制增强。该旧图不代表新通知外观。全部公开真机图已裁去无关状态栏或只保留本应用卡片，整屏私密通知只在会话 scratch。

v4 最后观察到计时 25:00、严格/监控关闭、`951101` 与计时前台服务消失，正式包版本、安装时间和 APK 哈希及显示设置未变，独立包与授权保留。这是 v4 阶段收尾；后续 v5 已安装实测，当前观测与边界见上方新报告。

## 历史模拟器与构建证据

- [v1 自动检查](build-verification.json)、[v1 日志](verification-logs.tar.gz)、[首轮设备报告](e2e-run/manual-e2e-results.json)：图标与授权识别；旧选择器滚动问题触发固定底栏修复。
- [v2 自动检查](build-verification-v2.json)、[v2 日志](verification-v2-logs.tar.gz)、[v2 核心报告](e2e-v2/manual-e2e-v2-results.json)、[v2 补测](e2e-v2-followup/manual-followup-results.json)：Chrome 拉回与名称记录、固定底栏、暂停不拦截、实际通知正文点击、legacy 同版本不误报。补测发现更新弹窗空白，随后修复。
- [v3 自动检查](build-verification-v3.json)、[v3 日志](verification-v3-logs.tar.gz)、[v3 门禁](delivery-gate-v3.json)：更新弹窗 widget 回归通过。保留 [debug 设备失败](e2e-v3/manual-download-results.json) 和 [原始采集](e2e-v3/initial-debug-device-attempt.tar.gz)。
- Profile 首次因系统服务缺失 [未执行](e2e-v3-profile/manual-profile-download-results.json)；保留 AVD 后完成 [恢复](e2e-v3-recovered/coldboot-recovery.json) 和 [下载闭环](e2e-v3-recovered/manual-profile-download-results.json)：系统进度 4%→10%→26%，重入 47%/48%，完成通知实际点击进入未知来源授权页，开关保持 OFF、未安装载荷。
- [v4 自动检查](build-verification-v4.json)、[v4 日志](verification-v4-logs.tar.gz)、[构建后文档差异](post-build-documentation-v4.json) 保留其 1267 文件快照和 2849 Flutter / 42 native 通过结果，仅作历史记录，不代替 v5。

旧模拟器 debug 启动/输入 ANR 根因未定位，见 [ANR 原文](e2e-v2/am_anr-events.txt)；系统恢复和 Profile 无 ANR 不证明 debug 问题已解决。夹具元数据为 `2.0.1`，实际载荷为 `2.0.0`，只验证传输与入口，不是生产升级。

## 收尾与剩余边界

上一轮 fixture / 截图 viewer 已按准确命令行关闭，端口 18763 / 18764 均不再监听，见 [清理记录](physical-xiaomi-20261105T021343Z/host-cleanup.json)。此前私密 viewer 也已关闭。本次重连补测未启动额外本机服务，未新增或删除 reverse 映射，未重启 ADB。

本次 v5 通知操作因动作行不可达未验收通过，具体系统渲染原因尚未确定；另有真正进程冷启动、长期锁屏/深度省电、搜索输入、下载进程退出续传与失败/取消/重试、旧 debug ANR、发布签名及正式覆盖升级等待验证。未执行生产部署或完整跨平台发布，本地提交不声称发布验收通过。

早期四份原始 logcat 因保留尾随空格改用 gzip 存储，解压字节与原文完全一致；历史 v4 索引保留原文哈希，最终 v5 索引记录压缩文件哈希，见 [早期日志存储记录](physical-xiaomi-20261105T021343Z/raw-log-storage-v5.json)。本轮另有通知补测日志和旧配置派生记录两份，均按原字节压缩、保留错误派生内容并更新引用及当前索引；物理结果和历史验证时间未改，见 [本轮日志存储记录](physical-xiaomi-20261105T021343Z/raw-log-storage-whitelist.json)。

[v5 本地提交门禁](delivery-gate-v5.json) 保存的是提交时 `local_commit_ready=true`、`product_device_acceptance=false` 的状态；后续重连实测另见上方新报告，当前仍不能声称通知操作已全部通过。
