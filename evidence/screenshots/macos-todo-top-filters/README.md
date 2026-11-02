# macOS 待办筛选置顶验证

修复原生 macOS 宽屏待办仍显示右侧筛选栏的问题。旧实现只按 `WebTarget.isWebBuild` 启用顶部布局；macOS 原生不是 Web，因而进入旧的宽屏侧栏分支。

现在 Web 与 macOS 使用同一顶部布局条件：从上到下为今日概要、自定义视图筛选、四象限 / 列表 / 看板页签、任务内容。其他原生平台的既有布局、四象限宽屏四列、筛选算法与任务数据均未改动。基线为 `8ac46df`，包含此前的紧凑悬浮窗和透明 Dock 图标修复。

## 检查结果

- 布局回归 22/22 通过：原 Web 基线 9 项、原生 macOS 11 项、Android 与 Linux 控制用例各 1 项。
- macOS 用例明确设置 `WebTarget.debugWebBuild = false`，通过 `TargetPlatformVariant.only(TargetPlatform.macOS)` 测试原生分支；不是把 Web 模式当作 macOS。框架负责恢复平台状态。
- 覆盖 default / liquidGlass 两套主题，1280×800、1600×900、1440×732、390×844、320×720 与 1.5 倍文字；Web 保留原四种视口，macOS 额外覆盖接近用户截图的 1440×732。
- 断言概要在筛选之上、筛选在页签之上、概要与筛选左右边界对齐，且没有侧栏 `VerticalDivider`。
- 选中、取消与清空「今日」时计数在 2/2 与 1/2 间正确变化，筛选区和页签位置稳定；象限菜单与快捷控件等高；切换三种任务视图后保持顶部顺序与任务内容。
- Android 窄屏保留原页签在概要之前的布局，Linux 宽屏保留原侧栏；无布局异常或溢出。
- 14 项现有待办布局 / 批量操作静态回归通过；全仓 `flutter analyze --no-pub` 无问题；两文件格式检查和 `git diff --check` 通过。

## 截图来源

三张 PNG 均由最终通过的同一轮测试，在 `DUOYI_TODO_LAYOUT_EXPORT` 指定目录后，对生产 `TodoScreen` 的 `RenderRepaintBoundary` 直接导出，DPR 为 1：

| 图片 | 配置 |
| --- | --- |
| `macos-1440-top.png` | 原生 macOS、1440×732、初始无筛选 |
| `macos-1440-today-filter.png` | 同一宽屏选中「今日」 |
| `macos-320-top.png` | 原生 macOS、320×720、1.5 倍文字 |

图中是测试夹具的「今日任务」「稍后任务」，不包含用户真实任务数据。这些是原生 macOS 平台配置下的 Flutter widget 离屏渲染，不是完整 AppKit 窗口或已安装客户端截图；完整 `.app` / 通用 DMG 的构建结果以本次修复提交对应的 GitHub Actions 为准。

未设置导出变量时常规测试不写图片。初轮测试的平台全局变量收尾失败已在测试夹具中改用框架 Variant 修正，未删减或降低布局断言；当前图片来自最终 22/22 成功运行。
