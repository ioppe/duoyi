# 统一底栏与全局圆体粗体

对应修改：移除首页专属底栏主题；全部应用界面改用随包分发的资源圆体 CN Bold（字重 700）。

## 问题与修复

- **底栏不一致**：`MainShell` 曾只在默认主题的今日页覆盖 `NavigationBarTheme`——高度 64、标签 10px、另一套选中色与指示形状，并把 `selectedIcon` 替换为未选中图标。因此今日页底栏与待办/习惯/我的不同。
- **修复**：删除该覆盖，四个一级页面共用主题中的 `navigationBarTheme`（高度 60、标签 11px、同一选中前景与指示形状、正常选中图标）。内容避让高度同步改为读取共享主题高度。
- **字体**：`_textTheme` 原为 `sans-serif` + 系统回退、常规字重。现统一 `ResourceHanRounded`（资源圆体 CN Bold），字重 `DesignTokens.fontWeightStrong`（700）；九套主题、共享控件、输入框、菜单、日期/时间选择、侧栏标签、图表提示一并覆盖。页面层级仍靠字号、颜色、间距区分。

## 验证

- `test/core/rounded_typography_test.dart`：九套主题 15 级 TextTheme、primaryTextTheme、AppBar/Dialog/SnackBar/Input/Menu/Tab/FAB/Rail/按钮样式、底栏选中态均断言 `ResourceHanRounded` + `w700`；并从 `FontManifest.json` 加载字体，校验 `OS/2.usWeightClass = 700`。
- `test/screens/desktop_web_shell_widescreen_test.dart`：默认主题与星穹铁道在 390×844（1.0×）和 320×720（1.5×）下逐个切换今日/待办/习惯/我的，断言应用到的 `NavigationBarThemeData` 等于主题共享值、总高 = 主题高度 + 底部安全区、选中图标在各页一致、每个标签字体/字重/字号/颜色符合共享样式。把 `lib/main.dart` 换回修改前版本时该用例失败（`height: 64` vs `60`，原因 "tab=0 must inherit the shared theme"）。
- `test/services/rounded_typography_static_test.dart`：扫描 `lib/`，禁止 `FontWeight.normal/w100–w600` 与 `fontWeightRegular`（PDF 的 `pw.FontWeight.normal` 单独保留），禁止页面内联 `fontFamily` 字面量；校验字体文件、OFL 与 pubspec 注册。
- 字体字形覆盖：ARB 与品牌文案中 839 个不同汉字全部在字库内。
- 完整 `flutter test`：**1813 passed / 1 failed**，唯一失败为既有基线 `test/screens/todo_batch_static_test.dart`（`_TodoViewMode.list =>` 缩进 28 vs 12），与本次改动无关。
- `flutter analyze`：No issues found；Web release 构建通过；服务端 `main.dart.js`、字体文件 SHA-256 与本地构建一致。

## 截图（Chromium，实际 Web 构建，390×844）

| 文件 | 内容 |
| --- | --- |
| `01-today-390.png` | 今日页，共享底栏 |
| `02-todo-390.png` | 待办页 |
| `03-habit-390.png` | 习惯页 |
| `04-mine-390.png` | 我的页 |
| `06-theme-picker-390.png` | 外观页：主题切换入口与圆体粗体列表 |
| `07-mine-dark-390.png` | 星穹铁道暗色 · 我的 |
| `08-today-dark-390.png` | 星穹铁道暗色 · 今日 |
| `10-today-320.png` | 320×720 窄屏 |
| `11-today-desktop-1440.png` | 1440×900 桌面侧栏 |
| `12-new-task-sheet-390.png` | 快速待办弹层：标题、输入文字、按钮、识别标签 |
| `13-today-with-task-390.png` | 新建任务后的列表与提示条 |
| `14-nav-comparison.png` | 四个一级页面底栏并排对照 |

`14-nav-comparison.png` 为 `01`–`04` 底部 74px 的并排裁切，可直观看到四个页面底栏只有选中项不同，字体/字号/颜色/间距/指示形状一致。

## 备注

- 字体为上游未经修改的 `ResourceHanRoundedCN-Bold.ttf`（v0.990，SIL OFL 1.1），来源与校验值见 `assets/fonts/README.md`。
- PDF 报告导出仍使用原有 `DroidSansFallbackFull.ttf` 与 `pw.FontWeight.normal`，不受界面字体变更影响。
- 生产环境未部署；本次仅提交到 Fork。
