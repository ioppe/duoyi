# 本地 Android 调试验证记录

记录日期：2026-10-26。本轮将日常测试接入免费的 Google 官方 Android Emulator，配合本地 Flutter 调试和热重载。最终采用 Android 15 / API 35 的硬件 GPU 配置。

应用源码基于 `ae5d53619de335cf66a455684a3270a6d00533fa`，版本 `1.1.54+140020`；本轮新增本地调试工具与文档，未改应用、后端、CI、版本或依赖锁文件。

## 最终环境与产物

| 项目 | 实际值 |
| --- | --- |
| 主机 | Apple Silicon Mac，Apple M3 GPU |
| 工具链 | Flutter 3.44.1 / Dart 3.12.1 / JDK 17 |
| 虚拟设备 | `duoyi_api35_arm64`，Pixel 5，Android 15 / API 35，ARM64，3072 MB |
| GPU | `hw.gpu.enabled=yes`、`hw.gpu.mode=host`，日志确认 Apple M3 |
| ADB 目标 | `emulator-5554`，shell 往返约 0.056 秒 |
| 屏幕 | 1080 × 2340，density 440 |
| 硬件加速 | Hypervisor.Framework，检查 exit 0 |
| APK | `build/app/outputs/flutter-apk/app-debug.apk`，168,223,341 bytes |
| APK SHA-256 | `bd0c2d3258e1cc73c839b26838cab48680690a69ac4b59e5e45d5c8de634793a` |
| 安装包身份 | `com.duoyi.duoyi`，versionName `1.1.54`，versionCode `140020`，debuggable |
| SDK | 编译/目标 API 36，最低 API 24；在运行 API 35 上验证 |
| Flutter 引擎 ABI | `arm64-v8a`；插件 AAR 另带部分其他 ABI 库 |
| 签名 | Android Debug，非正式发布签名 |

## 已执行的验证

- 本地 ARM64 调试构建成功，SDK、Kotlin、Gradle 首次缓存已补齐。发行版下载失败通过复用同版本 Gradle 8.14 缓存修复；TLS 验证与仓库内发布配置保持原有要求。
- `doctor`、`devices`、`run --dry-run` 通过，读取本机私有 profile，识别实际 Android 目标。
- 最终硬件配置中安装 APK 约 2.3 秒，本地存储初始化约 305 ms，原生截图可见“今日”首页；未执行账号登录。
- 实际点击底部“我的”图标中心，确认进入“我的”页和底部选中状态变化，再返回首页。一次留白处点击未切页，未冒充成功；输入命令本身的耗时不等同于页面动画耗时。
- 当前会话热重载成功：`Reloaded 0 libraries in 5,729ms`。当次应用代码没有变化，验证的是重载控制链路。
- 当前会话热重启成功：`Restarted application in 14,714ms`。
- 重复启动被拒绝，返回文档定义的错误码 `2`，未启动第二个会话。观察脚本最初误期望 `1`，核对契约后修正记录，没有修改入口行为。
- 旧会话 `stop` 成功结束并清理 PID；最终会话的调试连接和独占启动锁已确认。记录时官方模拟器和调试会话继续运行，当前实例无多仪 ANR 事件。
- 6 项独立守卫检查通过：显式缺失 profile、JRE 缺少 javac、Flutter 符号链接、PATH 兜底、Gradle home 目录隔离、stale/reused/own PID 拒绝。0 failures / 0 errors / 0 skipped；未向真实会话发送守卫测试信号。

最终调试入口 SHA-256：`47732a61bd03ec4bed742f9c4721f5d914b3a0541726fe96fa910cd2baded004`。

## 初始 API 36 实例的问题

初始 `duoyi_api36_arm64` 的模拟器日志明确提示 API 36 因 GLES 3.1 要求在本机强制软件渲染，实际使用 SwiftShader/llvmpipe。该实例曾在 `DuoyiWidgetRestoreReceiver` 的 `BOOT_COMPLETED` 恢复广播期间发生 ANR；前台 Activity 与 VM 连接仍存在，说明这两项不足以证明界面可操作。选择一次“等待”后提示一度消失，后续仍有迟缓，因此停止该实例并改用上述 API 35 硬件配置。

旧 AVD 数据、失败日志和截图保留，未关闭 ANR 检测、未修改 App 恢复逻辑，也未把切换环境宣称为修复了 API 36 广播问题。本次构建留下的私有 Gradle/Kotlin 编译后台进程已停止，未终止其他项目进程。

## 截图

- [初始 API 36 启动画面](2026-10-26-startup.png)
- [API 36 无响应提示（保留失败证据）](2026-10-26-anr.png)
- [API 35 硬件渲染启动](2026-10-26-api35-startup.png)
- [API 35 实际进入“我的”页](2026-10-26-api35-me.png)
- [最终就绪首页](2026-10-26-ready.png)

截图来自 `adb exec-out screencap -p`，对应原生 Android App。预览页仅展示截图；实际交互使用运行中的 Android Emulator 窗口。

## 范围

本轮验证本地开发链路、实际导航和入口守卫，未执行完整 Flutter/后端套件或整套设备门禁，也未验收真实手机的厂商省电、锁屏提醒、铃声震动和触控手感。模拟器可以按既有设备证据规范承担相应项目，但本记录不能自动替代完整门禁结论。

日常命令、本机 profile 与后续正式验收要求见 [本地 Android 快速验证](../../../docs/android-local-testing.md)。
