# Android 3×2 小组件裁切与四入口核验

2026-10-26，本地调试迭代，应用版本仍为 `1.1.54+140020`。本轮未提交、推送或发布正式安装包。

## 已验证结果

- 系统小组件选择器从实际显示 **28 widgets** 收敛为 **4 widgets**，展开后仅有今日待办、习惯、月历、专注四个标准 3×2 入口。
- 24 个历史入口使用 `hide_from_picker`，所有 28 个接收器继续保留启用。覆盖安装后，旧实例 ID **2、3** 及其物理 Provider 绑定均保留。
- 同一个 ID 2 实例由专注依次切至待办、习惯、日历，再回到专注。四次点击均使用最新原生控件位置；所有页面保持 Launcher 前台，没有启动 App。
- 四页均保持相同边界 `[64,466]–[767,1032]`，即 **703×566px**。系统字体比例为 1.0、密度为 2.75；原生文字行高已完整显示，内容没有与底栏重叠。
- 专注页保留统计数字、单位、专注入口、两行摘要和完整底栏。日历显示完整周行，包含当天 10 月 26 日。
- 最终恢复到桌面专注页；核验期间未发现 `com.duoyi.duoyi` 的 ANR 或崩溃事件。

| 元素 | 修复前可见高度 | 最终高度 |
| --- | ---: | ---: |
| 次数 | 13px | 40px |
| 分钟 | 13px | 40px |
| 下一轮 | 13px | 40px |
| 专注操作入口 | 88px | 77px，文字完整 |
| 最终底部各标签 | — | 77px |

以上为原生控件边界高度，不是应用字号设置。

## 截图

| 场景 | 证据 |
| --- | --- |
| 修复前专注文字裁切 | [before-focus-3x2.png](before-focus-3x2.png) |
| 最终专注页 | [final-focus-3x2.png](final-focus-3x2.png) |
| 最终待办页 | [final-todo-3x2.png](final-todo-3x2.png) |
| 最终习惯页 | [final-habit-3x2.png](final-habit-3x2.png) |
| 最终日历页 | [final-calendar-3x2.png](final-calendar-3x2.png) |
| 四页切换后恢复专注 | [final-focus-restored.png](final-focus-restored.png) |
| 修复前系统列表 28 项 | [before-picker.png](before-picker.png) |
| 修复后系统列表 4 项 | [after-picker.png](after-picker.png) |
| 四个实际条目名称 | [after-picker-expanded.png](after-picker-expanded.png) |

## 构建与源码绑定

- 工具链：Flutter 3.44.1 / Dart 3.12.1 / JDK 17，Android SDK 36；运行于官方 Android 15 / API 35 ARM64 Pixel 5 模拟器 `duoyi_api35_arm64`，Apple M3 GPU。
- 构建命令：`python3 scripts/flutter_with_config.py build apk --debug --target-platform android-arm64 --no-pub`。
- 最终构建时间：2026-10-26 11:16:12Z–11:16:28Z，退出码 0。
- APK：`build/app/outputs/flutter-apk/app-debug.apk`，202,156,188 字节，包名 `com.duoyi.duoyi`、版本 `1.1.54+140020`、debuggable，Flutter 引擎为 ARM64。
- 最终 APK SHA-256：`e910c6f9df8e4b8295733fd5ff7e48214e6b5dd9120f49df10d05851d32b2a91`。
- 已在设备上读取安装的 `base.apk` SHA-256，与最终构建包完全一致。
- 编译前后 65 个不同生产文件的哈希一致；设备验收结束后再次复核，仍全部一致。原始 96 行清单包含重复 XML glob，不能把它称作 96 个不同文件。
- 最终 `DuoyiWidgetLayout.kt` SHA-256：`5c66e393785c9b5508caac7bc3e19182dd3936ef7f0bb0c9246fe2de158f9600`。
- 宿主 ID 2 的尺寸范围为宽 255/447dp、高 131/205dp。竖屏使用 MIN_WIDTH + MAX_HEIGHT，横屏使用 MAX_WIDTH + MIN_HEIGHT；避免竖屏误用横屏较小高度。四个核心 Provider 使用官方双方向 `RemoteViews`，构建产物字节码已确认两套视图与单次外层更新。

## 检查结果

本轮有效结果为 **11 套件、140 项真实用例通过，0 失败、0 跳过、0 error**。隐藏的套件占位事件不计入用例数。资源契约和文案随需求同步后均已重新运行通过；最后原生方向预算修正后再次通过受影响的 40 项资源契约，其余 100 项对应代码未变。

| 套件 | 通过用例 |
| --- | ---: |
| android_widget_resources | 40 |
| home_widget_push_scheduler | 10 |
| home_widget_action | 14 |
| startup_performance_static | 1 |
| widget_preview_screen | 2 |
| brand_navigation_strings | 9 |
| ios_widget_resources | 10 |
| more_apps_widget_routes_static | 4 |
| widget_catalog | 3 |
| flutter_l10n_static | 4 |
| today_mine_smoke | 43 |

`dart analyze --fatal-infos` 无问题；5 个本轮 Dart 文件只读格式检查为 0 改动；`git diff --check` 通过；原生 Kotlin 和 Android 资源编译成功。未修改业务动作、账号/owner 校验、快照调度或 Flutter 默认正文 12 的既有改动。

## 核验边界

- 实际 UI 验收覆盖官方 API 35 Launcher 的竖屏 3×2 和系统字体比例 1.0。示例数据为未完成待办 0 项、习惯完成 0%、专注 0 次/0 分钟；未启动计时或执行完成/打卡动作。
- 受支持的横屏宿主 UI **尚未验收通过**：普通旋转请求未改变桌面方向，强制显示旋转后得到的组件边界与宿主声明尺寸不符，不作为有效横屏通过证据。两次尝试的设置均已恢复：`accelerometer_rotation=1`、`user_rotation=0`、`wm user-rotation=free`、`fixed-to-user-rotation=default`、`ignoreOrientationRequest=false`。最终重新确认竖屏 1080×2340、原 3×2 边界及完整内容均恢复。
- `hide_from_picker` 是 API 28+ 的宿主提示；旧启动器可能忽略，不能据此保证所有手机桌面都只列四项。隐藏历史入口保留已安装实例的兼容路径。
- 极小高度和大系统字体时，可选内容或整个日历网格可被收起，保证完整行；放大后的内容仍受所选密度上限约束。
- 本轮没有手机/国产 ROM 验收、完整发布设备门禁、正式签名检查或 GitHub Release 构建。

机器可读摘要见 [verification.json](verification.json)。
