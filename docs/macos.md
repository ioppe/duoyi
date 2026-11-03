# macOS 客户端与番茄计时悬浮窗

macOS 客户端使用现有 Flutter 应用和 Provider，复用待办、习惯、专注、日历、主题、本地存储及服务器连接。macOS 原生入口在 `macos/`，最低系统版本为 macOS 11。Android 桌面小组件与 Linux 系统托盘不作为 macOS 功能。

## 本地运行与构建

需要完整 Xcode、Xcode Command Line Tools、CocoaPods，以及 `config/toolchain.json` 固定的 Flutter 版本。仅安装 Command Line Tools 无法构建 Flutter macOS 应用。

先确认开发环境：

```bash
xcode-select -p
xcodebuild -version
pod --version
flutter --version
flutter doctor -v
```

如果 `xcode-select -p` 指向 `/Library/Developer/CommandLineTools`，安装完整 Xcode 并在 Xcode → Settings → Locations 选择对应 Command Line Tools。首次启动 Xcode，完成其组件安装。

从仓库根目录运行：

```bash
python3 scripts/project_config.py validate
python3 scripts/flutter_with_config.py pub get
python3 scripts/flutter_with_config.py run -d macos
python3 scripts/flutter_with_config.py build macos --release
```

Flutter 不在 PATH 时设置 `FLUTTER_BIN`。构建产物位于 `build/macos/Build/Products/Release/` 下的 `.app`。服务器初始地址从 `config/deployment.json` 注入，安装后仍可在登录页修改；支持本地模式、访问令牌与账号密码连接，不在构建参数中放置凭据。

## 待办页布局

macOS 原生待办页与 Web 共用顶部筛选布局：从上到下为今日概要、自定义视图筛选、四象限 / 列表 / 看板页签和任务内容。宽屏也不显示右侧筛选栏，窗口缩窄时继续按上下顺序排列。选中、取消和清空筛选保持筛选区及页签位置稳定，三种任务视图共享同一筛选状态。

## 创建弹窗

macOS 的共享新建、日期与选择弹层居中呈现，默认最大宽度为 720px，调用处的特定宽度上限继续生效；长内容在卡片内滚动。弹窗使用轻淡入和小幅缩放，支持关闭按钮、Escape、遮罩关闭与焦点循环，减少动态效果时直接显示最终状态。原生手机的底部面板与番茄悬浮窗分别保持各自交互。

## 使用悬浮窗

1. 打开「专注」计时页，点击标题栏的悬浮窗按钮。
2. 在个人化设置的「默认行为」区选择悬浮窗尺寸。大尺寸保留现有约 320×88 卡片和带文字的主按钮；紧凑尺寸高度为 64，宽度按当前时间和状态文字计算，普通倒计时从约 176 起，不再为长时长预留中间的大块空白。`1440:00` 等较长时间按需加宽，不缩小字号或按钮。主按钮与关闭按钮只显示 Apple SF Symbols，不显示可视中文，完整操作语义仍通过悬停提示和辅助功能标签提供。
3. 面板使用当前 App 的卡片底色、文字色、主按钮色、圆角和 Noto Sans SC 字体，显示状态与计时数值；切换主题时面板同步更新。运行时状态显示「暂停」，暂停后显示「已暂停」及「继续」；暂停保持剩余时间，继续接着本次计时。未开始时显示「待开始」和「开始」。正计时、短休与长休沿用主界面状态。
4. 按住时间、状态文字或面板空白处，用鼠标原生拖动。跨屏位置计算采用全局逻辑点，支持不同尺寸及上下错位的显示器，不按缩放比例换算像素。拖动期间不把面板钳回原屏；开始、暂停、继续与隐藏按钮保留各自的点击操作。
5. 面板始终置顶，可在不同桌面与全屏工作空间显示；位置会保存，再次打开时恢复。松手后仅在需要时恢复到目标屏可用范围，目标优先跟随鼠标所在屏，其次选择与窗口交集最大的屏幕，最后选择最近的剩余屏幕；尺寸切换和显示器断开后仍保持可见，普通计时更新不改变位置。
6. 点击面板的 × 或再次点击页面悬浮窗按钮，仅隐藏面板，正在进行的计时继续。重新打开时显示最新状态。
7. 主窗口红色关闭按钮隐藏主窗口并保留应用进程；点击 Dock 图标恢复主窗口。使用菜单「退出」或 `Command+Q` 才会退出应用。

切换页面、隐藏主窗口或隐藏面板不会另建计时器，也不会创建额外的专注记录。暂停、专注完成、休息切换、任务关联和会话记录均沿用 `PomodoroProvider`。运行计时时原生端抑制 App Nap，但不阻止 Mac 正常睡眠。

应用锁定、要求强制更新、切换账号或服务器时隐藏面板；应用锁定或强制更新期间不接受面板控制，恢复后由用户重新打开。未登录的本地使用模式同样可使用悬浮窗。按钮提示与面板辅助功能标签随应用中英文设置更新，窗口标题沿用当前主题的专注名称。

macOS 提醒使用系统通知授权。初始化通知服务时系统可弹出授权提示，应用的通知设置中也可显式申请；通知健康状态从系统读取，拒绝或撤销授权后显示未授权。允许通知后，番茄完成与休息结束沿用现有系统通知。可在 macOS 系统设置的「通知 → Duoyi」调整横幅、声音与权限。

## Dock 与 Finder 图标

macOS 的全部 AppIcon 尺寸由同一红白 Logo 母版生成 RGBA 图片，只移除红色圆角外的浅色画布，不改变品牌色、白色三块标志或应用身份。透明圆角直接露出 Dock / Finder 背景，在深浅背景上都不应出现白色方底或描边。图标生成与校验方式见 `docs/branding.md`。旧客户端需要用新 `.app` 覆盖更新并重新打开，才能加载修正后的资源。

## GitHub Actions 构建

`.github/workflows/build-apk.yml` 的主 `build` 是多端安装包的统一自动入口：推送 `main` / `self-hosted-skydrow` / `build/macos-dmg` 或 `v*` 标签都会触发，面向 `main` / `self-hosted-skydrow` 的 PR 保留原有触发规则。配置校验、分析与测试通过后，同一提交的 Android、macOS 安装包与 Web 桌面/手机包（`duoyi-web` 默认仅上传 artifact；`main` 的桌面 Web 包在服务端入口与唯一 Secret 配置完成后自动发布到自托管站点，GitHub Pages 仍只部署 `main`）并行构建，macOS 通过可复用的 `.github/workflows/build-macos.yml` 运行，并与 Android 使用同一份已验证的公开部署配置。手动运行主流程时，`build_macos` 默认开启，也可明确关闭；单独手动运行 `build-macos.yml` 仍可选择公开配置路径和初始服务器地址。

独立手动入口首次需要工作流文件进入仓库默认分支后才会显示；自动主流程在目标分支推送包含工作流与macOS源码的提交后生效。

构建分支 `build/macos-dmg` 也走上述统一流程，不再单独 push 触发 **macOS DMG**，避免同一提交重复构建 Mac 或漏掉 Android。子工作流只接受主流程调用和手动运行。无需为日常安装包创建或覆盖版本标签；除已配置自动发布的 `main` 桌面 Web 包外，分支推送仅上传 Actions artifacts。同一分支连续推送时只保留最新运行，尚未完成的旧运行会取消。

macOS 作业在分析与回归通过后运行，使用完整 Xcode 的 `macos-15` runner、固定 Flutter/Python 工具链和 CocoaPods，构建 Release 应用，并用 `lipo` 验证主程序同时包含 `arm64`、`x86_64`。常规运行上传 Actions artifacts；推送 `v*` 标签时，主流程等待 Android、Web、macOS 都成功，再把 DMG、ZIP 和校验文件一起加入 GitHub Release。独立 macOS 手动流程只上传 artifacts，不创建 Release、不发布标签。

`lipo` 的输入文件必须放在 `-verify_arch` 之前，避免文件路径被其变长参数当作架构名。CI 在构建前运行 `test/services/macos_packaging_workflow_test.dart`：用 `clang` 生成真实的 universal 和仅 arm64 的 Mach-O 文件，直接执行工作流中的校验命令，确认双架构通过、缺少 Intel 架构时拒绝。可在 macOS 本机运行 `flutter test --no-pub test/services/macos_packaging_workflow_test.dart`。

产物 `duoyi-macos-universal-unsigned` 包含：

- `duoyi-<版本>-<提交>-macos-universal-unsigned.zip`：保留 `.app` 文件权限的应用包。
- 同名 `.dmg`：应用及 Applications 快捷入口。
- `SHA256SUMS-macos.txt`：记录 DMG 与 ZIP 的 SHA-256 校验和，避免与其他平台的校验文件重名。

这是开发测试打包流程，未配置 Developer ID 签名或 Apple 公证；成功产出安装包不代表通过 Gatekeeper 验证。正式分发前应另行配置团队签名和公证。当前工作区的改动需要先进入所选构建分支，远端构建不会读取本机未提交文件。

下载入口：日常构建进入 **Actions → build → 对应运行 → Artifacts → duoyi-macos-universal-unsigned**；单独 macOS 流程也上传相同产物名。正式标签构建成功后，可从对应 **Releases** 页面直接下载 `.dmg`。DMG 内包含多仪应用与 Applications 快捷入口，拖入 Applications 即可安装。
- macOS 主窗口顶部标题栏也跟随当前 Flutter 主题背景色和文字色更新；切换默认、re0、深色等主题时不需要重启窗口，交通灯按钮与窗口拖动仍由 AppKit 原生管理。

## 实现边界

- `lib/services/pomodoro_floating_window_service.dart` 同时订阅 Provider 状态和 `timerTicks`。普通每秒 tick 不触发 Provider 的常规通知，因此两种监听均不可省略。
- `lib/widgets/pomodoro_floating_window_host.dart` 位于全局应用层，负责生命周期、语言、应用锁与身份变化；不依赖计时页持续挂载。
- Host 从当前 `ThemeData` 的卡片及 `FilledButton` 样式、`AppSurfaceStyle` 与 `DesignTokens` 提取颜色、边框、圆角和字号，通过快照中的 `appearance` 传给原生端；原生不再固定示例图配色。快照同时提供 `isPaused`、`stateLabel`、`resumeLabel` 与 `windowSize`，用于明确的暂停/继续展示和 large/compact 布局；字号在紧凑模式按原生布局上限收敛。
- `macos/Runner/MainFlutterWindow.swift` 通过 `com.duoyi/pomodoro_floating_window` 通道连接主 Flutter engine。
- `macos/Runner/PomodoroFloatingPanel.swift` 负责原生面板展示、拖动、位置恢复、large/compact 布局和 App Nap 活动，不自行计时。
- Dart 发送 `show`、`update`、`hide`、`dispose`；原生发送 `toggle`、`closed`。快照的 `windowSize` 缺失或未知时回落 large；尺寸变化只发送 `update`，原生原地 resize，并在必要时 clamp 到可见屏幕。`update` 不打开窗口，`closed` 不暂停计时。
- 跨屏坐标统一使用 AppKit 全局逻辑点，不按 Retina 像素比例换算。原生拖动不受旧屏上沿约束；拖动中的真实尺寸变化即时应用并保持实际 origin，位置回收与屏幕拓扑恢复延后至拖动结束。松手、重新显示或显示器变化后的可见性恢复使用实际屏幕几何，不依赖可能滞后的 `panel.screen`。负坐标、左侧/上方副屏、错位与热拔插由几何回归覆盖；本轮观察到的两块不同尺寸屏幕均为 2×，混合缩放与真实鼠标跨屏尚未实测。

不新增后端接口、账号数据或云同步字段。

## 验收

在 Mac 上可独立运行生产面板检查（不依赖 Flutter engine 或完整 Xcode）：

```bash
mkdir -p build/macos/native-smoke
swiftc -swift-version 5 -parse-as-library \
  macos/Runner/PomodoroFloatingPanel.swift \
  test/native/macos_pomodoro_panel_smoke.swift \
  -o build/macos/native-smoke/panel-smoke
build/macos/native-smoke/panel-smoke evidence/screenshots/macos-pomodoro
```

检查会显示并关闭自己的面板，验证控制回调、鼠标命中区域、显隐、长时长显示、主题应用、暂停/继续展示、large/compact 尺寸、紧凑符号按钮、位置恢复与尺寸切换后的可见边界，还覆盖合成显示器矩形下的负坐标、上方副屏、错位接缝与拔屏、`constrainFrameRect` 原样放行、拖动生命周期，以及拖动中真实尺寸变化保持实际 origin，同时生成 `panel-compact.png` 等渲染图与 `native-smoke.json`。可用 `DUOYI_FLOATING_THEME_EXPORT=<JSON路径> flutter test test/widgets/pomodoro_floating_window_host_test.dart` 导出真实主题快照，并把该 JSON 作为 smoke 程序的第二个参数，以真实 App 主题渲染。它不注入真实鼠标拖动（`realMultiDisplayDrag: false`），也不加载完整 Flutter 客户端。

人工步骤同步维护在 `docs/manual-regression-checklist.md` 的「macOS 番茄悬浮窗」节。截图和实际操作记录放入 `evidence/screenshots/` 下对应任务目录。面板单独编译检查、Dart 测试与完整 `.app` 构建是不同验证项，应分别记录结果；没有完整 Xcode 时不得把面板验证记为完整应用验证。本轮跨屏修复的 76 项原生检查、18 个方法探针位置与 8 张渲染图见 [原生跨屏验证记录](../evidence/screenshots/notification-multiscreen/native-validation.json)。

本次紧凑布局与 Dock 图标修复的原生渲染、尺寸对比和验证记录见 [macOS 修复证据](../evidence/screenshots/macos-compact-icon/README.md)。

macOS 待办顶部筛选的原生平台回归与渲染图见 [待办筛选置顶验证](../evidence/screenshots/macos-todo-top-filters/README.md)。
