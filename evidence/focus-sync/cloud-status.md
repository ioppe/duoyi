# 专注同步云图标调整

按本次界面要求，计时卡片底部不再常驻同步文字；云图标移至顶部阶段标题右侧。云朵使用白色填充和主题轮廓，在白色卡面上保持可见，按钮保留 44 的最小点击范围。

| 状态 | 图标 | 点击提示 |
| --- | --- | --- |
| 未登录 | 未同步云图标 | 登录后同步多端专注 |
| 已登录但未同步 | 未同步云图标 | 离线未同步 |
| 已登录且权威快照/实时连接正常、无未确认错误 | 同步云图标 | 多端专注已同步 |

图标提供同文案的可访问名称和悬停提示；点击使用应用内浮动 SnackBar。提示内容走中英文 I18n/ARB，不触发登录跳转或提交计时命令。

## 已执行验证

- 32 项定向测试通过：状态控件、专注页布局、本地化与字体守卫。
- 状态测试覆盖未登录、本地兼容模式、离线、连接但无快照、未确认错误、已同步，以及退出后残留连接标记；逐项点击并核对文案。
- 窄屏 240、2 倍文字、深色主题提示布局通过；整页检查云图标与阶段标题同排、位于圆环上方，底部没有常驻状态文案。
- 改动的 4 个 Dart 文件静态分析：`No issues found`，启用 fatal infos。
- `flutter gen-l10n` 与 `git diff --check` 通过。
- 本地 Flutter Web 预览重新构建成功，8 个更新文件与工作区逐项 SHA-256 匹配。
- 浏览器真实页面确认新图标位于“专注中”右侧、底部文字消失。实际点击已同步云图标后，页面变化记录捕获到新增“多端专注已同步”提示；使用事件记录避免 4 秒短提示在下一次取图前消失。
- 文档核对确认 `docs/focus-runtime-sync.md` 与三态判定和文案一致。

[实际浏览器页面截图](../screenshots/focus-sync-cloud-status/header-cloud.jpg)

测试入口：

```bash
flutter test --no-pub \
  test/widgets/focus_sync_status_test.dart \
  test/screens/pomodoro_focus_layout_static_test.dart \
  test/core/i18n_test.dart \
  test/services/rounded_typography_static_test.dart --reporter expanded

dart analyze --fatal-infos \
  lib/widgets/focus_sync_status.dart lib/screens/pomodoro_screen.dart \
  lib/core/i18n.dart test/widgets/focus_sync_status_test.dart
```

完整日志与预览源码清单在本会话 scratch：`focus-cloud-icon-tests.log`、`focus-cloud-icon-analysis.log`、`focus-cloud-preview-build.log`、`focus-cloud-preview-source.json`。

## 范围

本轮为状态呈现与点击提示的 UI 改动，未更改共享运行态、命令、计时和结算行为。本地浏览器预览已更新；手机验证 APK 没有在本轮重新构建或安装。此前的 11 项实机结果对应其原 APK，不作为这次新 UI 的实机证据。改动保留在 `feature/account-focus-sync`，未提交或推送。

## 标题间距修正

初版把最小高度为 44 的云按钮放入标题行，导致“0 次专注”下移。已将标题与次数保留在紧凑两行文字列中（间距 `DesignTokens.spaceXxs`），云按钮独立放在整列右侧，保留原有点击范围。

本次 15 项定向测试通过，包括正常和 2 倍字号下对标题/次数实际边界、间距、左对齐的检查。三态提示行为保持不变。

静态分析无问题，浏览器预览已重建并检查：[修正后的紧凑标题截图](../screenshots/focus-sync-cloud-status/header-cloud-compact.jpg)。

## 后续真机核验

已随后将最新云图标及紧凑头部布局构建、安装到独立手机验证包，并在实际 1.25 系统字号下检查布局、点击提示和时长滚动。此前“手机包尚未更新”的说明仅对应前一轮浏览器调整时点；最新结果见 [手机布局核验](../focus-cloud-mobile/README.md)。
