# macOS 紧凑悬浮窗与 Dock 图标修复验证

本次修复针对紧凑悬浮窗中间留白过多，以及 macOS AppIcon 圆角外烘焙浅色画布的问题。应用标志仍为批准的 `#C85656` 红色圆角块与白色三块几何图形。

## 原生面板

同一套实际 Flutter 主题与 Noto Sans SC 字体下，直接编译生产 `macos/Runner/PomodoroFloatingPanel.swift` 并运行原生 smoke。没有用 HTML 重画面板。

| 状态 | 修改前 | 修改后 |
| --- | --- | --- |
| 普通 `24:58` 倒计时 | 固定 236×64 pt | 176×64 pt |
| 长时长 `1440:00` | 固定 236×64 pt | 按需增宽至 197×64 pt |
| 大尺寸 | 320×88 pt | 320×88 pt |

普通紧凑窗减少 60 pt（约 25%）宽度，数字到主按钮实测间距为 15.5 pt；长时长间距为 6 pt，文字完整显示。时间字号仍为 26 pt，状态字号在紧凑布局中仍为 11 pt，按钮沿用原有尺寸。每秒同位数更新保持窗口宽度和位置，暂停、显示/隐藏、尺寸切换及屏幕边界处理沿用原有行为。

- `panel-compact-running.png` / `panel-compact-paused.png`：修复后的普通倒计时，352×128 像素，176×64 pt @2x。
- `panel-compact.png`：修复后的 `1440:00`，394×128 像素，197×64 pt @2x。
- `before-panel-compact.png`：旧代码同主题下的长时长，472×128 像素，236×64 pt @2x。
- 其他 `panel-*.png`：大尺寸、运行/暂停及另一套实际主题的原生渲染。
- `native-smoke.json`：59 项检查通过，包括可见字形居中、短间距、长时长、每秒尺寸/位置稳定、英文状态与屏幕边缘扩宽；所有记录的字形居中偏差均为 0.25 pt。原生编译和运行 stderr 均无警告或 AutoLayout 冲突。

Flutter 层同时通过 7 项 Host 测试和 19 项计时桥接测试，覆盖真实主题快照与面板操作仍交由原有计时 Provider 处理。

## 图标

macOS 的 16 / 32 / 64 / 128 / 256 / 512 / 1024 像素 AppIcon 从同一 SVG 母版生成 RGBA，直接在透明画布上渲染红块和白色标志，移除圆角外的浅色底。16 像素资源四角保留极低覆盖度的抗锯齿（alpha 2/255），其他尺寸四角为 0；不改几何、品牌色或应用身份。母版、参考图、iOS、Android、Linux 和 Web 图标在本次生成后均保持原字节。

`icon-light-dark.png` 使用真实旧/新 PNG 在深浅背景上合成对比；它是资源检查图，不是系统 Dock 截图。

图标测试 8/8 通过，`python3 scripts/sync_app_icons.py --check` 通过且运行前后资源哈希一致，确认只读；全仓 `flutter analyze --no-pub` 无问题，Dart 格式与 `git diff --check` 均通过。使用系统 `iconutil` 打包为 `.icns` 再解回后，10 份图像表示都保留 RGBA、透明角落、不透明品牌色和标志。

## 来源与验证边界

逐文件来源见 [PROVENANCE.md](PROVENANCE.md)。旧基线为 `c4f5a2e`；本次工作区基于保留后续桌面修复的 `ae0ce27`，这两版之间的原生面板与图标资源相同。

这些图片是生产 AppKit 视图的独立原生渲染和图标资源对比，不是完整 Flutter 客户端、实际系统 Dock 或真实鼠标拖动的截图。本机仅有 Command Line Tools，完整 `.app` 和通用架构安装包由现有 GitHub Actions macOS 工作流构建；构建结果以修复提交对应的运行和产物为准。旧安装需要用新应用包覆盖更新并重新打开，才能取得新的 Dock 图标。
