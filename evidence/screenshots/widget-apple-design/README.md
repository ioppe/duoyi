# 苹果风小组件布局核验

本轮使用 `frontend-design` 制定视觉方案，并同时实现 Android 四核心 RemoteViews 与 Flutter 预览。当前工作区仍为 `fix/android-input-settings-device-test`，版本 `1.1.54+140020`；没有提交、推送、发布或升版本。

## 设计结果

- 24dp 圆角、轻中性表面，通常 14dp 内边距，月历 12dp；短实例按真实高度收紧。
- 18dp 红白品牌标记配模块标题。浅色文字使用 `#1C1C1E` / `#6E6E73`，保留主题强调色及深色/图片渲染路径。
- 待办：数量与单位分层，空态居中；非空任务使用轻标记与完整行。
- 习惯：单一主百分比，配今日完成率和连续天数。
- 专注：左主时间、右次数/分钟小统计，淡色“前往专注”入口。
- 月历：完整当前月份、周一对齐、日期右上角事项数，0 隐藏；不按密度删周。
- 四标签使用轻分段导航，选中项局部高亮，仍由原生广播在同一实例内切页。

## 检查结果

19 个受影响 Flutter suite 共 **173 个不同用例通过，0 失败、0 跳过**。其中资源守卫 40、旧预览 2、新布局 5、月历预览 5、目录 3、日历快照 4、日期模型 22、后台动作 14、推送排程 10；其余覆盖 iOS 资源、排版、品牌、本地化、账号、入口与启动守卫。资源守卫修复换行敏感匹配后单独复跑，其余 18 套 133 个已通过结果保持。

`dart analyze --fatal-infos`、只读格式和 `git diff --check` 均退出 0。`flutter analyze` 的 LSP 服务两次解析初始化消息失败，改用固定 Dart 的全项目分析取得 `No issues found!`；失败日志保留，不算分析通过。

Kotlin 与 Android 资源首轮独立编译成功，修复后的完整 Debug APK 和 Web 构建也均成功。29 个本轮生产源文件在构建前后以及最终取证后摘要一致。未运行无关后端测试或正式签名发布门禁。

## 实际设备证据

设备为官方 API 35 ARM64 模拟器 `emulator-5554`，Pixel 5，density 2.75，系统字号 100%。稳定核验均使用 widget ID 2，实际宿主仍为 `DuoyiTodoWidgetProvider`；ID 3 的详细历史实例也保留。组件边界 `[64,466][767,1032]`，即 **703×566px**。

- [四页布局及对比](index.html) / [原图组合](overview.png)：四页均显示完整四标签，取证时 Launcher 保持前台，无应用 ANR，文字边界均在卡内。
- [待办空态](after-todo-empty.png)：空态图形、标题、提示居中，数量 0 使用辅助色。
- [习惯](after-habit.png)：0% 主完成率、今日完成率与连续 0 天。
- [专注](after-focus.png)：25 分钟、0 次、0 分钟与“前往专注”完整。
- [完整月历](after-calendar.png)：2026 年 10 月，1–31 日各一次，星期与实际日期对齐。
- [真实待办](after-todo-content.png)：通过离线 TodoProvider 添加三个独立 ID，数量 3，标准密度显示两条完整任务行。
- [真实角标](after-populated-observe.png)：同三条事项使 27 日显示“3项”，其余 30 天不显示正数角标。
- [清理后待办](after-todo-cleaned.png) / [清理后月历](after-calendar-cleaned.png)：只删除本轮三个 ID，Provider 恢复 0 条，待办空态恢复，27 日角标清零，完整月份保留。

日期格的可访问性信息合并在 `widget_calendar_day_cell` 的 `content-desc` 中，例如 `2026-10-27，3项`；不能用压缩树中缺失的日期子 TextView 判断日期丢失。页面切换后的首次过渡截图 `initial-calendar-transition*` 不计为稳定验收；`after-todo-populated.png` 是一次前台变化导致的未完成取证，不用于证明布局。启动期间曾观察到 `/habit` 路由断言，稳定四页底栏核验期间未复现，本文不据此声称 App 所有深链均已验收。

## 构建和安装

```bash
python3 scripts/flutter_with_config.py build apk --debug --target-platform android-arm64 --no-pub
python3 scripts/flutter_with_config.py build web --debug --no-pub
```

APK：`build/app/outputs/flutter-apk/app-debug.apk`，**202,210,424 B**；SHA256：

```text
8f1a2b50f28c037de40ac1bf0eede6a11380b3cd612c8779d290ba18f4893ba3
```

设备已安装 `base.apk` 摘要与此完全相同，版本 1.1.54 / 140020，debuggable，target/compile SDK 36，min SDK 24。Flutter 引擎为 ARM64；其他 ABI 仅有插件附带 native library。

Web 完整构建成功，18655 调试服务在热重启后出现模块加载停滞，经核验 PID/cwd 后重启同一项目服务恢复。最终实际显示登录页，见 [Web 刷新截图](web-refreshed.jpg)；未登录，所以未将该截图当作组件预览验收。Flutter 组件预览的浅深色、320 宽×1.3 字号与三密度完整月份由实际 widget tests 覆盖。

## 证据边界

Android 原图覆盖浅色主题、当前竖屏 3×2 尺寸、空态/非空、完整月历及清理恢复。深色 Flutter 预览已测试，原生深色、原生图片背景、受支持横屏、其他 Launcher/ROM、真机、iOS WidgetKit 和正式签名发布未在本轮执行。旧 HTML 设计样稿仅用于视觉设计，不是设备证明。
