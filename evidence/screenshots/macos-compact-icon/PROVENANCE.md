# macos-compact-icon 证据来源

生成时间：本次 after 验证（worktree fix/macos-compact-panel-icon, HEAD ae0ce27 + 未提交修复）。

## after-* 实际产物（本次运行）
由 `verification/after/panel-smoke`（本工作区 `macos/Runner/PomodoroFloatingPanel.swift`
SHA-256 `f56c5f8e…c3fe6` + `test/native/macos_pomodoro_panel_smoke.swift` SHA-256 `0c01f75f…3b070`
以 `swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos11.0` 编译）在 repo 根运行生成，
第二参数为真实 Flutter 导出 `verification/flutter-theme-snapshots.json`（1293 字节，fixture 键
`default`/`alternate`，由实现前基线 host test 用 DUOYI_FLOATING_THEME_EXPORT 导出）。
- `native-smoke.json`：59/59 checks，退出码 0
- `panel-ready.png` / `panel-running.png` / `panel-paused.png` / `panel-long-duration.png`
  / `panel-alternate-theme.png`：large 卡（320×88 @2x）
- `panel-compact.png`：compact 1440:00（197pt 宽，@2x 394px）
- `panel-compact-running.png`：compact 24:58 running（176pt 宽，@2x 352px）
- `panel-compact-paused.png`：compact paused（176pt 宽，@2x 352px）

## before-* 基线对照（复制，不是新截图）
来源：`$PI_SCRATCH_DIR/macos-compact-icon/verification/before/real-theme/`——旧基线
`web-auto-deploy/worktree` HEAD `c4f5a2e` 用同一真实主题 JSON 运行旧 `panel-smoke` 的产物
（49/49 checks，退出码 0）。
- `before-panel-*.png`：旧 large 卡（640×176 @2x）与旧 compact 卡 `before-panel-compact.png`（236×64，@2x 472px）
- `before-baseline-native-smoke.json`：旧基线 49-check 结果
- `before-flutter-theme-snapshots.json`：与本次相同的主题 fixture 副本

## 边界
这些是原生 NSView 离屏 capture（`cacheDisplay`），不是完整 `.app` 截图，也不含真实 Dock 安装效果；
`native-smoke.json` 自报 `fullApplicationBuildVerified=false`、`realMouseDragVerified=false`。

## icon-light-dark.png（应用图标深浅底对照）
来源：把**真实资源 PNG**直接合成到浅色 `#F5F5F7` 与深色 `#1E1E20` 底板上——旧图为
`web-auto-deploy/worktree` HEAD `c4f5a2e` 的 `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{16,32,64,128,256,512,1024}.png`，
新图为本工作区同名文件（1024 一栏缩至 256 以便阅读，其余按原始像素尺寸摆放），程序为 Pillow 合成。
**这不是系统 Dock 截图**，也不代表安装后的实际 Dock 渲染；它只用于比较旧（不透明满幅浅底）与新（透明圆角、红底白 glyph）资源本身的差异。
