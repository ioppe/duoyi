# 本地 Android 快速验证

本页描述日常迭代用的本地 Android 闭环：官方 Android 模拟器（Android Emulator，免费、随官方 SDK 提供）或开启 USB 调试的真机，配合固定 Flutter 工具链做 `flutter run`、热重载、热重启和退出。

这条闭环用于缩短改一版看一眼的周期，**不能替代**发布门禁。完整测试、正式签名和设备证据门禁见文末。

## 边界

- 只做本机构建与运行：`run` 复用 `scripts/flutter_with_config.py`，所以公开配置的注入方式与 CI 相同（同一个 helper、同样是 `--dart-define-from-file`，而不是同一条 CI 命令），不需要另外维护一份 defines。
- 不改全局环境：脚本只为子进程设置 `FLUTTER_BIN`、`JAVA_HOME`、`ANDROID_SDK_ROOT`/`ANDROID_HOME`、`GRADLE_USER_HOME`、`FLUTTER_STORAGE_BASE_URL` 和 `PATH`；后两项可选，未配置时不会写入。脚本不写 Flutter 全局配置、不改 shell rc、不下载工具链、不创建或删除 AVD；它确实会写仓库 `build/` 下的构建产物和 `build/local-dev/` 的 PID/锁文件。
- 不接管设备：`reload`/`restart`/`stop` 只对已记录且校验通过的 Flutter 会话发信号（`SIGUSR1`/`SIGUSR2`/`SIGINT`），不会 `killall` 或对未校验的 PID 动手。`run` 和信号控制需要 POSIX（macOS/Linux），其他平台会给出明确报错，`devices` 与 `doctor` 仍可只读使用。模拟器管理与设备清理仍由本人手动完成。

## 一次性准备（以 Apple Silicon macOS 为例）

版本以 `config/toolchain.json` 为准（Flutter 3.44.1、Java 17），脚本启动前会校验，不匹配直接报错而不是继续跑：

1. 固定版 Flutter：把 3.44.1 解压到固定目录并至少运行一次 `<flutter>/bin/flutter --version`，让它生成 `bin/cache/flutter.version.json`（脚本用它核对 `frameworkVersion`）。
2. Java 17：安装后可用 `/usr/libexec/java_home -v 17` 找到，或显式设置 `JAVA_HOME`。
3. 官方 Android SDK：安装命令行工具、`platform-tools`、`emulator`、对应 `platforms`/`build-tools` 与系统镜像，并设置 `ANDROID_SDK_ROOT`（或使用 macOS 默认的 `~/Library/Android/sdk`）。`sdk_root` 必须是完整 SDK 根目录，指向 `platform-tools` 子目录会被明确拒绝。
4. 官方 AVD：用 Android Studio 的 Device Manager 或 `avdmanager` 创建一次即可，之后手动启动：

```bash
"$ANDROID_SDK_ROOT/emulator/emulator" -avd duoyi_api35_arm64 -gpu host
```

本机使用的官方 AVD 名为 `duoyi_api35_arm64`（Android 15 / API 35 Google APIs ARM64、Pixel 5、3072 MB 内存），已设置 `hw.gpu.enabled=yes`、`hw.gpu.mode=host`，实际使用 Apple M3 GPU。构建 SDK 为 36，与运行镜像 API 35 兼容；运行镜像不必与编译 SDK 相同。其他机器以实际兼容的镜像与 GPU 模式为准。脚本不负责创建、启动、删除 AVD。等模拟器完成开机、`adb devices -l` 里出现 `device` 状态后再进入日常循环。

## 可选的私有机器配置

路径因机器而异，写在被 Git 忽略的 `config/android-local.local.json`（`.gitignore` 已包含 `config/*.local.json`）。只放本机路径，不放账号、密钥或令牌：

```json
{
  "flutter_bin": "~/Library/Developer/duoyi/flutter-3.44.1/bin/flutter",
  "sdk_root": "~/Library/Android/sdk",
  "java_home": "/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home",
  "device_id": "emulator-5554",
  "gradle_user_home": "~/Library/Developer/duoyi/gradle",
  "flutter_storage_base_url": "https://storage.flutter-io.cn"
}
```

六个键都可省略；未设置的键不会写入或改动任何环境变量，保持原有环境与默认行为。取值优先级为：显式环境变量（`FLUTTER_BIN`、`ANDROID_SDK_ROOT`/`ANDROID_HOME`、`JAVA_HOME`、`ADB_BIN`、`GRADLE_USER_HOME`、`FLUTTER_STORAGE_BASE_URL`）> 该私有文件 > 约定默认位置。约定默认位置只在对应路径真实存在时才采用（Flutter 目录名跟随 `config/toolchain.json` 的版本），否则继续回退到 PATH 上的 `flutter`/`adb`；显式设置但无效的 ENV 或私有配置值会直接报错，不会被静默跳过。`gradle_user_home` 必须是 `~` 展开后的绝对目录、已存在且位于仓库之外；`flutter_storage_base_url` 必须是 https URL，且不允许带账号密码、查询参数或片段；`java_home` 必须是含 `bin/java` 与 `bin/javac` 的完整 JDK。未知键会被拒绝，避免把拼写错误当成生效配置。

显式传入 `--config PATH` 时该文件必须存在，否则直接报错（`--config file not found`），不会静默改用其他 profile；不传 `--config` 时才使用上面这个可选默认文件，文件不存在就当作没有私有配置。

由于环境变量优先，若 shell 里已有指向非 17 的全局 `JAVA_HOME`，脚本会按策略使用它并报版本不符。此时在命令前临时提供正确的 17 即可，脚本只会把它作用到子进程，不改全局环境：

```bash
JAVA_HOME=$(/usr/libexec/java_home -v 17) python3 scripts/android_local_dev.py run
```

## 可选的隔离 Gradle 与 Flutter 镜像

公共构件仓库不可用时（例如 Google Maven、Maven Central 在本机 TLS 中断），可以在仓库外维护一份隔离的 Gradle home，并在上面六个键里指向它：

- `gradle_user_home`：脚本只把它作为 `GRADLE_USER_HOME` 传给 Flutter 子进程，并要求该目录位于仓库之外。仓库映射（例如 `init.d/local-repositories.gradle`）与代理设置等 `gradle.properties` 都由本人在该私有目录维护；脚本不创建、不修改、不下载该目录或仓库内 Gradle 文件里的任何内容，也不改动仓库内的 Gradle 配置、CI 或默认 `~/.gradle`。构建产物仍会写到仓库的 `build/`。
- `flutter_storage_base_url`：脚本只把它作为 `FLUTTER_STORAGE_BASE_URL` 传给子进程，用于 Flutter 构件下载源（例如 `https://storage.flutter-io.cn`）。

两者都只是作用到子进程的环境变量：未设置时保持原有环境与默认行为，`doctor` 与 `run --dry-run` 会显示实际生效的值（URL 只做校验后的展示，不含凭据）。仓库内的 Gradle 配置、CI 工作流与公开默认值不因此改变。

## 命令

```bash
python3 scripts/android_local_dev.py devices    # 列出 adb 目标与已装 AVD，不做选择
python3 scripts/android_local_dev.py doctor     # 逐项检查 Flutter/SDK/adb/Java/目标，别名 status
python3 scripts/android_local_dev.py run        # 启动 flutter run，写 pid 文件
python3 scripts/android_local_dev.py reload     # SIGUSR1 热重载
python3 scripts/android_local_dev.py restart    # SIGUSR2 热重启
python3 scripts/android_local_dev.py stop       # SIGINT 退出并等待进程结束
```

目标选择顺序：`--device SERIAL` > 私有配置里的 `device_id` > 仅当两者都未提供时才自动使用唯一的 `device` 状态目标。显式或配置指定的 ID 必须是已连接、状态为 `device` 的 Android 目标，否则直接失败——即使还有别的可用设备也不会改用它。没有目标、多个目标、`unauthorized`、`offline` 都会给出可操作的报错，不会猜串口、不会自动选择浏览器/桌面设备。

`run` 的相关选项：

```bash
python3 scripts/android_local_dev.py run --device emulator-5554
python3 scripts/android_local_dev.py run --apk build/app/outputs/flutter-apk/app-debug.apk
python3 scripts/android_local_dev.py run --dry-run
```

- `--apk` 把已有调试 APK 通过 `--use-application-binary` 交给 Flutter，适合只改了 Dart 侧的联调；需要 Flutter 自己重新构建时不要传。
- `--dry-run` 在校验完工具链与目标后只打印将执行的命令、解析出的路径与目标，不构建、不启动、不发信号。
- 会话信息（PID）记录在 `build/local-dev/flutter.pid`，已被 Git 忽略；启动用 `build/local-dev/launch.lock` 上的 POSIX `flock` 做原子去重。锁文件常驻不删（进程退出即释放），拿不到锁、或在锁内复查发现已有校验通过的会话时，`run` 直接失败并提示改用 `reload`/`restart`/`stop`，不会开第二个。

信号控制只有在 PID 文件里的进程仍然是本工作区的 Flutter 运行进程（命令行含 `flutter_tools.snapshot` 或 `flutter run`，且包含该 PID 文件的绝对路径）时才会执行；否则报错并且不发任何信号。过期或复用的 PID 不会被当成有效会话。

脚本退出码：`0` 成功；`1` 环境未就绪（`doctor` 至少有一个 `[fail]`，`[info]`/`[warn]` 不影响就绪）；`2` 配置、工具链或会话校验失败；Ctrl-C 中断 `run` 返回 `130`。`stop` 在超时内没等到进程退出时报错并保留 PID 标记（标记始终反映真实状态，不会被提前清掉）。`run` 会原样返回 Flutter 子进程的退出码。

命令里的 `python3` 可以换成 `PYTHON_BIN` 指定的解释器；`run` 通过 `scripts/flutter_with_config.py` 以继承 stdio 的子进程启动 Flutter，所以终端里的 `r`/`R`/`q` 仍由那个 Flutter 会话处理。包装脚本只用标准库，`config/toolchain.json` 里的 Python 版本是 CI 后端要求，本地不强制。

## 日常循环

1. 手动启动官方模拟器（或插上调试真机），确认 `python3 scripts/android_local_dev.py doctor` 没有 `[fail]`（可以存在 `[info]`/`[warn]`）。
2. `python3 scripts/android_local_dev.py run`，等首次构建安装完成。
3. 改 Dart 代码后在运行会话里按 `r` 热重载、`R` 热重启，或在另一个终端用 `reload`/`restart`；结束用 `q` 或 `stop`。
4. 改了 `android/` 下的 Kotlin、插件、权限、字体或 manifest 等原生部分时，热重载不生效，需要重新构建并安装（重新执行 `run`，或先用 CI/本地命令产出调试 APK 再 `run --apk`）。

登录、同步、备份等需要账号的行为只由本人在模拟器/真机界面上操作；不要在文档、配置或脚本里记录账号密码。

## 模拟器能覆盖什么

适合：字体与排版、各主题与文案、布局与导航、列表/表单交互、页面切换、本地数据持久化与重启后状态、截图与 logcat 排查、桌面启动器里的 widget 外观。

**仍需真机**：提醒的电源状态与闹钟行为、锁屏/全屏提醒、通知栏与渠道的实际表现、震动与铃声、实体键盘与触控手感、厂商 ROM 差异。设备证据脚本在连接模拟器或真机时都可运行，但这些真机专属行为仍需真机确认。

## 与正式门禁的关系

迭代期的 SDK、构建与热重载结果不等于任何设备门禁通过：只跑过 `run` 或只构建出调试 APK，都不能证明通知栏、全屏闹钟、铃声播放或桌面 widget 的实际行为。

设备门禁这一环节**模拟器同样可以承担**：`docs/device-regression-evidence.md` 要求在连接 Android 手机**或模拟器**时运行 `scripts/device_regression_check.sh`，并按该文档与 `scripts/validate_device_evidence.sh android` 的要求采集全部必需证据。是否通过取决于“实际执行并采集到全部证据”，而不是设备类型；只装了 SDK/AVD、只构建过 APK、只验证过热重载都不构成设备门禁通过。

- `scripts/alignment_regression_gate.sh`：Flutter 测试 + 后端测试 + analyze + 调试 APK 构建 + 设备回归，发布前整体门禁。
- `scripts/generate_device_readiness_report.sh`、`scripts/device_regression_check.sh`、`scripts/android_device_evidence.sh`、`scripts/validate_device_evidence.sh android`：设备证据链路与校验；就绪报告只能解释缺失的外部前提，不能替代设备证据。
- GitHub Actions 的完整测试与正式签名（`DUOYI_KEYSTORE_*`）流程不变；本地调试 APK 是调试签名，与 CI 的 release 签名不同。

提醒的电源状态与锁屏/全屏行为、震动与铃声、实体键盘与触控手感仍以真机为准，这些项未在真机实际验证前不要记成通过。迭代稳定后仍要按原流程跑完整测试与正式签名构建，并按上述文档完成设备证据采集；真机手工回归清单见 `docs/manual-regression-checklist.md`。

## 安装冲突与数据

本地调试 APK 与线上正式签名的 APK 签名不同，直接覆盖安装可能失败。遇到冲突时不要自动卸载或清数据：优先在模拟器上做本地调试，正式验证用真机 + 正式签名包。卸载会清掉应用数据（本地任务、偏好、登录态），需要保留数据时改在模拟器里试验。

## 故障处理

| 现象 | 处理 |
| --- | --- |
| `Flutter executable ... missing or not executable` | 安装固定版 Flutter，或在私有配置/`FLUTTER_BIN` 指向真实可执行文件 |
| `... reports Flutter ... but config/toolchain.json pins ...` | 安装或指回 `config/toolchain.json` 钉住的版本；不要改项目去迁就本机版本 |
| `Pinned version metadata missing` | 对该 Flutter 先跑一次 `--version` 生成 `bin/cache/flutter.version.json` |
| `does not exist` / `platform-tools/ is missing` / `only has platform-tools/` | 补齐官方 SDK 组件；`sdk_root` 必须是完整根目录 |
| `does not match the pinned Java 17` | 安装 Java 17 或把 `JAVA_HOME`/`java_home` 指到 17 |
| `Java home ... has no executable bin/javac` | 换成完整 JDK 17（只有运行时的 JRE 会被拒绝） |
| `No Android device or emulator attached` | 先手动启动 AVD 或插好真机，再 `doctor` |
| `is 'unauthorized'` | 在设备上接受 USB 调试授权 |
| 多个目标 | 显式 `--device SERIAL`，脚本不会替你挑 |
| `No verified Flutter run session ...` | 先用 `run` 起一个会话；脚本不会对未校验进程发信号 |
| `--config file not found` | 显式给的路径不存在；改正路径，或去掉 `--config` 使用可选默认文件 |
| `did not answer within ...s`（adb / emulator -list-avds / ps） | 检查对应工具或设备是否响应后重试；脚本不会自动重试 |
| `Another local Android launch already holds ...` | 已有启动在进行；等它结束或先 `stop`，不要并行启动 |

## 当前状态

2026-10-26 最终已在 Apple Silicon Mac 的官方 Android 15 / API 35 ARM64、Pixel 5 AVD `duoyi_api35_arm64` 上完成以下实际验证：

- 固定 Flutter 3.44.1、完整 JDK 17 与 Android SDK 就绪；`doctor`、`devices`、`run --dry-run` 通过，目标为 `emulator-5554`。虚拟设备使用宿主机 Apple M3 GPU，ADB shell 往返实测约 0.056 秒。
- 本地构建 `1.1.54+140020` 调试 APK 成功，编译/目标 SDK 为 36、最低 API 为 24；在运行 API 35 上安装约 2.3 秒，首页正常显示，使用调试签名和 ARM64 Flutter 引擎。
- 实际点击进入“我的”页并返回“今日”页，原生截图确认页面与底部选中状态切换；未执行账号登录。
- 当前硬件渲染会话的热重载确认 `Reloaded 0 libraries in 5,729ms`（本次未修改应用代码），热重启确认 `Restarted application in 14,714ms`。这些是本次测量值，不代表所有后续修改都耗时相同。
- 重复启动按契约返回会话校验错误码 `2`，原会话未被替换；旧会话的 `stop` 正常结束并清理 PID。最终会话已确认调试连接和持有中的独占启动锁，记录时保留该会话供继续测试。
- 配置缺失、完整 JDK、Flutter 符号链接、PATH 兜底、Gradle 目录隔离及错误 PID 拒绝共 6 项守卫检查通过，0 跳过；守卫检查不替代 Flutter 业务测试或设备门禁。

初始 API 36 实例在本机被模拟器强制切到 SwiftShader/llvmpipe 软件渲染，并出现 `BOOT_COMPLETED` 小组件恢复广播超时与无响应提示。该实例已正常停止，数据、日志和失败截图保留；最终改用上述 API 35 硬件配置，当前实例未记录多仪 ANR，启动与导航已实际验证。应用原生恢复逻辑未修改，因此不把环境切换描述为已经修复 API 36 的恢复广播问题。

截图与本轮范围见 [本地 Android 调试验证记录](../evidence/screenshots/android-local-testing/README.md)。本轮覆盖的是本地开发链路；未运行整套设备门禁，也未验收真实手机的厂商省电、锁屏提醒、实体键盘与触控行为。完整设备结论仍需按 `docs/device-regression-evidence.md` 实际执行并采集全部必需证据。
