# 专注与休息布局实现证据

分支：`feature/focus-rest-layout`。基线：创建分支时最新 `main` 的 `5d1f816f0235ebad85038f2de4d61d93cdadd652`。本次改动保持本地，未提交、推送、合并、打版或部署。

## 实现范围

- 手机：阶段与完成次数、独立同步云按钮、160 逻辑像素的简洁计时环、可横向滚动的时长选项、休息摘要、主要操作、轻量辅助区。
- 桌面：左侧计时与操作，右侧时长、休息安排与辅助选项；窄屏回到单栏。当前全局导航壳保持原样。
- 设置：短休息、长休息、长休息间隔、默认关闭的 5∶1 联动及两个自动开始开关；共享 Android/iOS 底部面板与 macOS/Web 居中规则。内容独立滚动，标题、关闭与保存区固定。
- 独立草稿、范围校验、取消/关闭不写入、保存失败保留草稿、账号代次检查；只合并六项休息字段，保留其他设置和当前运行/暂停状态，不发送远端计时命令。

具体生效时机见 [专注与休息安排](../../docs/focus-rest-settings.md)：本地下一阶段读取最新设置；远端当前轮次保留服务端快照，下次客户端开始携带更新。

## 验证结论

- Flutter 固定版本 `3.44.1`；使用物理 ASCII 源码副本，未更改 SDK 或全局配置。可执行源码与副本逐文件核对 SHA-256，见 [source-hashes.json](source-hashes.json)。
- 22 个相关测试文件，共 222 项用例。最后整组运行有 220 项通过、2 项失败；修正真实字体测试夹具和列表滚动定位后，两个受影响文件的 19 项全部通过，无未解决失败。未把重复执行的用例重复累计。
- `flutter analyze --no-pub`：`No issues found`。改动 Dart 文件格式检查及 `git diff --check` 通过。
- 一次代码复审与一次文档核对已完成。补齐空输入步进、UI 保存失败用例、回归清单层级、需求/设计和中英翻译，未另启广泛复审。
- 测试范围、命令、最后各次结果、几何值与截图哈希见 [validation.json](validation.json)。

## 实际 Flutter 图像

[打开截图画廊](../screenshots/focus-rest-layout/index.html)。10 张 PNG 均由实际 `PomodoroScreen` 与 `showFocusRestSettingsSheet` 渲染，加载项目 Noto Sans SC 和 Material 图标字体，未用 HTML 设计稿冒充运行结果。

覆盖 390×844、320×720（系统文字比例 150%，叠加 Android 12/14 基准）、1280×800；包含专注、短休息、长休息、面板初始/滚动、放大文字和 300px 键盘余高。几何断言确认：手机主操作位于摘要下；内容滚动后保存区不动；键盘抬起后保存区可触达；桌面面板宽度不超过 464 且水平居中。

捕获夹具保存在 [capture_test.dart.txt](capture_test.dart.txt)。复现时将其复制到经哈希核对的 ASCII 项目 `test/focus_rest_capture_test.dart`，设置输出目录后运行：

```bash
FOCUS_REST_SCREENSHOTS="$PI_SCRATCH_DIR/focus-rest-screenshots" \
  flutter test --no-pub test/focus_rest_capture_test.dart
```

夹具使用模拟 SharedPreferences 与本地计时状态，未连接真实账号，未控制生产计时器。

## 证据边界

这些图像是 Flutter widget test 的实际渲染；平台呈现和 Android 字号通过测试目标模拟。测试宿主仍为 macOS，原生通道没有实际插件，不能据此证明系统权限、系统键盘、通知、浮窗或安装包行为。全局状态栏与主导航壳不在此夹具内；HTML 确认稿上的预览工具栏也不是产品功能。

本次未跑整包测试、E2E、Android 实机或完整 macOS 原生应用回归。手动检查项仍在 [回归清单](../../docs/manual-regression-checklist.md) 中保持未勾选。本次未修改后端、发布版本、应用标识、签名、图标或生产数据。

原 `main` 工作区仍在基线提交，其 180 个未跟踪文件保持保留；历史 `evidence/` 文件及原哈希清单未改写。
