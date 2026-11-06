# Android 下拉主动同步：小米实机验证

修正版同一 APK 的 **16 项定向实机检查已分阶段通过**，无未执行项目或未决产品问题。完整结构化结果见 [verification-summary.json](verification-summary.json)，原始截图见 [截图对照](index.html)。

## 设备与候选产物

- 真机：Xiaomi 24129PN74C，Android 16 / API 36，arm64-v8a；设备号 `2df52c4c`。
- 保持手机原显示设置：1200×2670、520dpi、系统字体倍率 1.25。
- 测试包：`com.duoyi.duoyi.pullsynccheck`，显示名称“多仪·下拉同步验证”，版本 `2.0.0 / 140023`，debug 签名。
- 实际启动 Activity：`com.duoyi.duoyi.MainActivity`；native namespace 没有改动。
- 修正版 APK SHA256：`04a48f180eb0b203c469781b1f6b4e5ef445cb5550a7055e0d0f777ea07df23a`。
- 源码基线：`4602528a49191b5e3bae2f32b8603fc8956f42ef` 加本工作区未提交的下拉同步改动和空模板兼容修正；精确输入见 [源码哈希清单](fixed-v2/source-manifest.json)。
- 后端：项目真实 FastAPI 接口，独立 SQLite、专用测试账号，通过 USB reverse 访问本机 `127.0.0.1:18781`。为单独观察手动同步，关闭该测试账号客户端的自动同步，并抑制测试服务的 SSE 变更事件；慢请求与 HTTP 503 由隔离服务注入。

## 通过项目

四个目录使用同一修正版 APK，分别保留每段执行的截图、UI 树与结果。表中的“通过”指相应断言最终实际通过，不能据此将中断过的整段脚本描述为一次连续全通过。

| 编号 | 验证内容 | 结果与证据 |
| --- | --- | --- |
| 05 | 今日页下拉可见转圈、远端新增到达，等待期间再次下拉只产生一次请求 | 通过；[转圈](fixed-v2/05-today-remote-and-singleflight-spinning.png)、[内容更新](fixed-v2/05-today-remote-and-singleflight-after.png) |
| 06 | 无本地新修改时重复下拉真实执行 `/api/sync/pull` | 通过，HTTP 200；[结果](fixed-v2/physical-results.json) |
| 07 | 服务端返回 HTTP 503 时，结束转圈并显示失败反馈 | 通过；[失败反馈](fixed-v2/07-failure-feedback-after.png) |
| 08 | 服务恢复后可再次下拉成功，本地内容保留 | 通过；[恢复结果](fixed-v2/08-retry-recovery-after.png) |
| 09 | 今日页空目标标签也可下拉 | 通过；[截图](fixed-v2/09-empty-goal-tab-after.png) |
| 10 | 横向切换内容标签不触发同步 | 通过，0 次同步请求；[结果](fixed-v2/physical-results.json) |
| 11 | 习惯空列表下拉主动拉取整个账号 | 通过，`/api/sync/pull` HTTP 200；[截图](fixed-v2/11-habit-empty-global-sync-after.png) |
| 11b | 习惯页拉取的待办变化在返回今日待办后显示，切标签不额外同步 | 通过，额外同步请求为 0；[跨页数据](fixed-v2-rest/11b-global-data-after-tab-return.png) |
| 12 | 专注页下拉同步 | 通过；[截图](fixed-v2-rest/12-focus-page-after.png) |
| 13 | 我的页顶部下拉同步 | 通过；[截图](fixed-v2-rest/13-mine-top-after.png) |
| 14 | 列表中部普通向下滚动不触发同步 | 通过，0 次同步请求；[截图](fixed-v2-final/14-middle-scroll-no-sync-after.png) |
| 15 | 待办四象限页面下拉同步 | 通过；[截图](fixed-v2-final/15-todo-list-route-after.png) |
| 16 | 日历页面下拉同步 | 通过；[截图](fixed-v2-routes/16-calendar-route-after.png) |
| 17 | 随手记空列表下拉同步 | 通过；[截图](fixed-v2-routes/17-notes-empty-route-after.png) |
| 18 | 目标管理空列表下拉同步 | 通过；[截图](fixed-v2-routes/18-goals-empty-route-after.png) |
| 19 | 倒数日空列表下拉同步 | 通过；[截图](fixed-v2-routes/19-countdown-empty-route-after.png) |

最终返回今日待办：[最终手机画面](fixed-v2-routes/20-final-today.png)。

## 真机发现并修复的问题

第一版 APK 能显示转圈并取到远端内容，但连续刷新时一直上传 `quick_capture_templates`。诊断请求体发现，客户端无模板时构造 `{"updatedAt":"","items":[]}`，真实服务端的既有合并逻辑返回 `{"items":[]}`，导致集合哈希长期不相等。

客户端现仅在版本非空时写入该集合的 `updatedAt`，与服务端既有形态保持一致；模板内容、有效时间戳以及带版本的显式清空均保留。未修改后端接口或数据库结构。

- 新增最小回归在修正前确实失败：[失败日志](pull-sync-empty-template-before.log.gz)。
- 修正后含三个新增回归在内的 **106 项定向 Flutter 测试全部通过**：[测试日志](pull-sync-after-device-fix-tests.log.gz)。
- 修正版物理英文路径副本执行 Flutter 3.44.1 静态分析：`No issues found`，并成功构建 APK：[构建与分析日志](fixed-v2/build-and-analysis.log.gz)。
- 快照复制时校验 1277 个常规文件；构建后复核 17 个关键源码、测试、锁文件及身份配置，无非预期差异；仅隔离包名、应用名称、深链三处身份配置不同：[源码绑定检查](fixed-v2/source-verification.json)。

原始工具日志以 gzip 无损归档；解压后的字节校验值见 [日志归档清单](log-archives.json)。

## 分阶段执行说明

- 首轮 `v1` 因真实的空模板哈希差异中止，原始失败现场保留。初版脚本曾先记录基础请求成功再检查端点；该记录顺序也已修正，最终 06 在端点断言通过后才记为通过。
- `fixed-v2` 完成 05–11 后，测试仍停在横滑切到的“目标”标签，错误地在那里查找待办；显式选择“今日待办”后，11b 验证数据已更新且没有额外同步。这是测试导航前置条件问题。
- `fixed-v2-rest` 完成 11b/12/13 后遇到系统安全锁屏。未尝试绕过锁屏；用户手动解锁后继续。
- `fixed-v2-final` 完成 14/15 后，待办页面没有脚本预期的屏内返回控件；按安卓正常系统返回回到今日后，继续 16–19。
- `fixed-v2-routes` 的四项全部通过并正常退出。所有原始中止记录均保留，未覆盖或改写为成功。

## 日志与正式版保护

- 当前测试进程范围内未发现 `FATAL EXCEPTION`、fatal signal、未处理异常、Flutter 溢出；系统事件缓冲中未发现该测试包的 crash / ANR：[日志扫描](fixed-v2/log-scan.json)。
- 正式包 `com.duoyi.duoyi` 的 APK 哈希、版本与安装时间均未改变，没有卸载、降级、清除数据或复制正式版账号数据。
- 分辨率、密度及字体倍率保持原值：[保护核对](preservation-check.json)。
- 后端请求日志仅记录测试请求路径、集合名、耗时和状态，不含令牌或密码：[请求记录](backend-requests.jsonl)。
- 已清理手机共享存储中本任务创建的临时 UI XML；测试应用保留在手机上，本地测试后端继续运行供本次体验。

本次结论限定为这台小米真机、当前显示设置和隔离 debug 测试包的手动同步行为；不代表正式签名升级、线上真实账号服务或其他设备/主题已完成验证。尚未合并 main 或发布安装包。
