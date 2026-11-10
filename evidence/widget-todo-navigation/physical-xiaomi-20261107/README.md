# 小组件待办返回导航：USB 实机验证

最终结果：**v2 APK 的 8 项实机用例全部通过**。真实小组件任务行进入详情，系统返回一次到普通待办清单，再返回一次到 App 今日主页；清单不显示“隐藏应用 / 返回我的”。

## 设备与候选

- Xiaomi `24129PN74C`，Android 16，USB `2df52c4c`；1200×2670、520 dpi、系统字号 1.25，测试未调整这些值。
- 分支 `fix/widget-todo-back-navigation`，基线 `55e9bb634f30fbff1b9d71178b056d729f52265d`，包含未提交的本次修复。
- 隔离 debug 包 `com.duoyi.duoyi.widgetnavcheck`，显示名“多仪·导航验证”，Activity 保持 `com.duoyi.duoyi.MainActivity`。通过 MIUI 原生小部件列表放置待办实例 **568**，桌面第 16 页。
- v2 APK SHA256：`08bbd337ae07ea1031fe70b70b6f19af7b1af9fe1f07503ba0ec999c1fb1ed41`，160614468 字节。手机已安装 APK 的哈希一致。
- 使用应用快捷创建路径生成两条独立本地测试任务；没有登录生产账号。测试后任务 B 名称为 `Widget back test B EDITED`，A/B 均未完成。
- [候选元数据](v2/candidate.json) / [1258 文件源码哈希](v2/source-manifest.json) / [测试数据](v2/fixture.json)。副本仅改包名、显示名和外部 scheme 声明三处身份；原生小组件仍以显式 Activity Intent 发送原有 `duoyi://` 链接。

## 实机结果

设备时间 2026-11-07 02:20:29–02:29:31（UTC+08:00）。用例分段执行，第二段修正输入法候选提交后复测编辑与确认；全程使用同一 v2 APK，未更换产品代码。

| 用例 | 结果 | 断言与证据 |
| --- | --- | --- |
| 暖启动任务行 | PASS | [详情](v2/11-warm-detail.png) → [普通清单](v2/12-warm-back-list.png) → [今日主页](v2/12-warm-back-home.png)；[结果](v2/warm-result.json) |
| 进程死亡后冷恢复 | PASS | [点击前进程不存在](v2/20-cold-process.json)，真实任务点击打开[详情](v2/21-cold-detail.png)，再返回[清单](v2/22-cold-back-list.png)、[主页](v2/22-cold-back-home.png)；[结果](v2/cold-result.json) |
| 小组件标题入口 | PASS | [清单](v2/31-title-list.png)只需一次返回到[主页](v2/32-title-home.png)；[结果](v2/title-result.json) |
| 详情中再次从小组件进入另一任务 | PASS | 打开任务 B 后，两次返回仍到主页，不叠加清单；[结果](v2/repeat-result.json) |
| 应用内清单一致性与重入 | PASS | [应用内清单](v2/51-app-internal-list.png)与[小组件清单](v2/52-widget-list.png)的四象限/列表/看板/筛选控件一致，重入后一次返回主页；[结果](v2/ordinary-list-result.json) |
| 失效 ID | PASS | 显式失效深链进入兜底，返回清单再到主页；[结果](v2/missing-result.json) |
| 编辑、保存、桌面刷新、重开 | PASS | [候选提交后真实字段](v2/72-edit-committed.png)、[磁盘值](v2/edit-storage-check.json)、[桌面新名称](v2/74-edited-widget.png)、[重新进入详情](v2/75-edited-reopen.png)，两次返回主页；[结果](v2/edit-result.json) |
| 完成确认取消 | PASS | 显式 `confirm=1` 深链弹[确认窗口](v2/81-confirm-dialog.png)，取消到清单再返回主页；[结果](v2/confirm-result.json) |

每张截图旁保留同名 XML，断言基于真实页面节点和系统 `KEYCODE_BACK`。前六项中的暖/冷/标题/重复/一致性均通过真实桌面小组件点击；失效 ID 和确认分支通过显式深链补测。

## 本轮发现并修复

首版返回链暖启动通过，但进程死亡后的恢复出现“这个待办不存在或已被删除”。[首版现场](v1/failure-cold.png)及[运行时深链缓存](v1/cold-v1-link-cache.json)证明：正确任务 URI 已到达，同时旧的 `duoyi://widget` 仍被重放，磁盘任务并未丢失。

v2 在带 ID 的待办入口等待 `TodoProvider` 本地加载，且用导航序号和账号代际取消过期请求；读取期间抑制同步脏标记。Android `onNewIntent` 转发新链接前清除旧的 `pendingInitialDeepLink`，避免随后 `takeInitialLink` 重放。v2 冷恢复实机通过。

首版测试脚本还存在“点击后未等待启动便断言前台”的时序问题，已改为等待详情。v2 编辑初次尝试中，微信输入法将 ADB 字母保留在候选窗口，返回取消了未提交候选；[原失败记录](v2/input-method-attempt/edit-result.json)及[候选截图](v2/72-keyevent-observation.png)保留。加入空格提交候选、确认真实字段内容后，编辑/保存/重开通过。此修正只影响测试输入方式，没有为此改产品代码或降低断言。

## 其他验证与保留检查

- 82 个相关自动测试通过（17 导航/接线、51 Android/iOS 小组件契约、14 详情/主页）；3 个修改 Dart 文件静态分析无问题，Android debug 构建成功。
- [构建与分析日志](v2/build.log.gz)、[实机执行日志](v2/physical-cases.log.gz)、[已有详情/主页测试日志](v2/existing-tests.log.gz)。
- 首版原始日志与绑定记录采用[无损归档映射](log-archives.json)提交；`SHA256.json` 保留原始路径和哈希，映射中的 `.gz` 解压后必须与原始哈希一致。
- [限定进程日志检查](v2/log-check.json)：未发现 FATAL EXCEPTION、Fatal signal、Unhandled Exception、RenderFlex overflowed 或 Another exception was thrown；测试包无对应 crash buffer 记录。[原始进程日志](v2/app-process.log.gz)。测试 URL 为没有后端的本机回环地址，因此日志有预期的配置连接失败，未据此宣称后端验证通过。
- [正式版保留核验](production-preservation.json)：正式包 `com.duoyi.duoyi` 的 APK 哈希、路径、版本、安装更新时间均与[测试前](device-before.json)一致；分辨率、密度、字号不变。没有卸载、清除或降级正式包，也没有操作既存同步测试包。
- 测试结束保留“多仪·导航验证”及其小组件，前台为隔离应用今日主页，便于人工检查。正式版不会自动包含此未发布修复。

## 覆盖边界

此次验证使用隔离 debug 包和本地测试数据，不能代替生产签名升级、真实账号同步或其他 ROM 验证。旧底栏偏好迁移、未保存瞬间重入、账号代际取消已有自动测试，但没有单独实机执行；侧滑返回手势、单独点击空白区域、iOS 设备未覆盖。没有跑全仓测试或正式发布门禁。
