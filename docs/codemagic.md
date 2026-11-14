# Codemagic 云端构建

根目录 `codemagic.yaml` 是 Codemagic 的 bootstrap 配置，与 `.github/workflows/` 的 GitHub Actions 流水线并存、互不替代。GitHub Actions 仍是发布门禁；Codemagic 只是额外的云端构建入口。

## 工作流

| workflow ID | 触发方式 | 产物 |
| --- | --- | --- |
| `duoyi-ci` | `main` 分支 push 自动触发（`cancel_previous_builds: true`） | 测试日志、debug APK、Web desktop/mobile tarball、`SHA256SUMS.txt` |
| `duoyi-macos` | 仅在 Codemagic 手动启动 | 通用架构 ad-hoc DMG/ZIP、`SHA256SUMS-macos.txt`、`duoyi-macos-validation.json` |
| `duoyi-android-release` | 仅在 Codemagic 手动启动 | 签名 release APK（split-per-abi + 通用）、AAB、`SHA256SUMS-android.txt` |

三个工作流都跑同一套前置：Python 3.12（缺失时用 Homebrew 安装 `python@3.12`）、独立 venv 安装 `backend/requirements.txt` 与 `scripts/requirements-icons.txt`、`config/toolchain.json` 与实际 Flutter/Java/Python 比对、`scripts/project_config.py validate`、`flutter pub get --enforce-lockfile`、图标校验、`flutter analyze`、Flutter 全量测试、后端单元测试（独立 SQLite，`DUOYI_DB_PATH=build/codemagic/backend-tests.sqlite3`、`DUOYI_ENV_FILE=''`、`APP_UPDATE_REPOSITORY=''`）。日志写入 `build/codemagic/logs/`。

产物命名带版本与短 SHA（`git rev-parse HEAD` 前 8 位），例如 `duoyi-0.1.0+142026-<sha8>-debug.apk`。配置里没有 `publishing` 段：不发布 GitHub Release、不发邮件、不部署生产环境。

## 首次接入

1. 在 Codemagic 用 GitHub App 授权接入目标仓库（即被推送的 Fork，例如 `ioppe/duoyi`），并选择包含 `codemagic.yaml` 的分支。
2. 应用设置页选择 **Check for configuration files**，确认检测到根目录 `codemagic.yaml`（文件必须在仓库根目录，且已提交）。
3. 在应用内的 **Start new build** 弹窗中选择分支，workflow 选 `duoyi-ci`，再确认启动。默认只跑 `duoyi-ci`；`duoyi-macos` 与 `duoyi-android-release` 需要显式选择，避免同时占满构建额度。
4. 自动触发还需要在应用设置里为该仓库创建 webhook（**Create webhook**）；未建 webhook 时只能在 UI 手动启动。

云端启动本身需要 Codemagic 账号对目标仓库有访问授权。Codemagic API Token 只在用 REST API 触发构建时才需要，`codemagic.yaml` 不引用它，也不要在仓库或文档里写入任何 token。

## 产物下载

构建页面的 **Artifacts** 区可下载文件；批量产物会打成一个 ZIP。按工作流：

- `duoyi-ci`：`build/codemagic/artifacts/` 下的 debug APK、`duoyi-web-<version>-desktop.tar.gz`、`duoyi-web-<version>-mobile.tar.gz`、`SHA256SUMS.txt`，以及 `build/codemagic/logs/*.log`（analyze、测试、构建日志）。
- `duoyi-macos`：`build/macos/packages/` 下的 DMG/ZIP 与 `SHA256SUMS-macos.txt`，另加 `build/codemagic/duoyi-macos-validation.json`。
- `duoyi-android-release`：`build/codemagic/artifacts/` 下的 release APK、AAB 与 `SHA256SUMS-android.txt`。

下载后可用 `shasum -a 256 -c <SUMS 文件>` 核对（SUMS 内是相对文件名，先进入对应目录再校验）。

## 测试 APK 的限制

`duoyi-ci` 里的 APK 经 `scripts/flutter_with_config.py build apk --debug` 构建，使用与其他客户端相同的公开部署配置，是 **debug 签名测试包**，旁边会生成 `<apk>.txt` 说明 `signed_with=debug`。它不是 release APK，不能用于上架或覆盖安装使用正式签名的包；构建失败时也不会用 debug 包冒充 release。需要 release 包时走 `duoyi-android-release` 或原有 GitHub Actions 流程。

## macOS 产物与人工验证

`duoyi-macos` 复用 `.github/workflows/build-macos.yml` 的打包与验证逻辑：定位唯一的 `build/macos/Build/Products/Release/*.app`，用 `PlistBuddy` 读取可执行名与版本，`python scripts/macos_adhoc_package.py prepare --app` 做 ad-hoc 重签名，分别 `lipo -verify_arch arm64` 与 `x86_64`，再用 `ditto` 出 ZIP、`hdiutil` 出带 `/Applications` 链接的 DMG，最后用 `check-packages` 生成校验报告。

产物仍然是 **ad-hoc 签名、未公证**，应用身份（bundle id、entitlements、签名身份约定）不变；不要把它当成 Developer ID 或已公证发行包。`check-packages` 会在真实 ZIP/DMG 上执行启动、窗口出现、3 秒存活与经典 keychain 读写删校验；只有 `codesign` 通过不算完成，脚本失败即构建失败（无 `continue-on-error`、无 `ignore_failure`）。人工验收时下载 DMG 后仍需在本机启动确认首次运行、权限弹窗与 keychain 行为。

## Android 签名 Secrets

`duoyi-android-release` 引用环境变量组 `duoyi_android_signing`，需要在 Codemagic（应用或团队变量）里配置四个变量，并在 UI 中标记为 Secret：

- `DUOYI_KEYSTORE_BASE64`：release keystore 的 base64（`base64 -i release.jks | tr -d '\n'`）
- `DUOYI_KEYSTORE_PASSWORD`
- `DUOYI_KEY_ALIAS`
- `DUOYI_KEY_PASSWORD`

工作流第一个步骤只检查这四个变量是否存在，缺失立即失败且不打印值；`android/app/build.gradle.kts` 会把 `DUOYI_KEYSTORE_BASE64` 解码到 `build/generated/signing/duoyi-release.jks`，因此不需要额外生成 `key.properties`。任何情况下都不会退回 debug 签名，也不要索要或粘贴明文密码到聊天、issue 或文档里。

## 当前边界

- 是否通过以所选提交的 Codemagic 构建日志、状态及产物为准；配置被识别不等于构建成功。
- 没有自动部署、没有应用商店上传、没有生效的自动发布；Codemagic 只构建并产出安装包，不参与部署。生产部署协议仍是 GitHub Actions 同一次 run 的限定 Web 发布与 `scripts/deploy_*`，但 GitHub Actions 的 `main` push 构建及其后的自动 Web 部署当前已停用（`main` 不在 push 构建分支白名单内），恢复前不会自动发布任何生产内容。
- `DUOYI_UPDATE_REPOSITORY` 等产品行为未改动，迁移更新源不在本配置范围内。
