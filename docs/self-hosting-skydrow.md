# 自托管构建：todo.skydrow.site

Fork：<https://github.com/ioppe/duoyi>。本地工作分支为 `self-hosted-skydrow`；`origin` 指向本 Fork，`upstream` 指向原项目。

公开部署参数统一放在 `config/deployment.json`：

- 后端：`https://todo.skydrow.site`
- 更新仓库：`ioppe/duoyi`
- Web 路径：`/`
- 后端运行器：Docker，容器名 `duoyi-backend`

配置架构、优先级、密钥边界和迁移规则见 [configuration.md](configuration.md)。域名与更新源不再作为业务代码的默认字面量。

## 开发与验证

按照 `config/toolchain.json` 安装工具链，然后在仓库根目录执行：

```bash
python3 scripts/project_config.py validate
python3 scripts/flutter_with_config.py pub get
python3 scripts/flutter_with_config.py analyze
python3 scripts/flutter_with_config.py test
python3 scripts/flutter_with_config.py run
```

工具不在 PATH 时，设置 `FLUTTER_BIN` 为可执行文件的绝对路径。可用 `git fetch upstream` 获取原项目更新，再按分支流程合并。

## Android

```bash
python3 scripts/flutter_with_config.py build apk --debug
```

正式包需要自己的签名密钥与 `android/key.properties`：

```bash
python3 scripts/flutter_with_config.py build apk --release
```

GitHub Actions 需要在本仓库配置 `DUOYI_KEYSTORE_BASE64`、`DUOYI_KEYSTORE_PASSWORD`、`DUOYI_KEY_ALIAS`、`DUOYI_KEY_PASSWORD`。Secrets 不随 Fork 复制；后续 APK 应持续使用自己的同一份签名密钥。
安装版登录页默认显示服务器地址和访问令牌。首次可在网页版登录并进入“我的 → 个人资料 → 访问令牌”创建令牌，再填写 `https://todo.skydrow.site` 和令牌连接。也可使用安装版的账号密码入口。服务器地址保存在本机，可在退出登录后修改，无需重新打包。

## Web

构建入口读取 Web 布局与 base href；Web 接口默认使用当前站点同域后端：

```bash
python3 scripts/flutter_with_config.py build web --release
```

需要移动布局时显式覆盖：

```bash
python3 scripts/flutter_with_config.py build web --release \
  --dart-define=DUOYI_SERVER_URL= \
  --dart-define=DUOYI_WEB_TARGET=mobile
```

CI 同样使用部署配置；根路径自托管包和 GitHub Pages 子路径包分别构建。仓库 Variables 仍可覆盖部署参数，手动工作流的 `same_origin` 用来显式选择空后端地址。

## 语言与应用时区

默认都跟随浏览器/系统：系统语言为中文时显示简体中文，其它语言回退英文；应用时区取系统时区。用户可在“我的 → 个性设置 → 日期与日历”里把界面语言固定为简体中文或 English，或把应用时区固定为某个 IANA 时区；选择保存在本机（`duoyi_locale_v1`、`pref_app_timezone_mode` / `pref_app_timezone_iana`），切换后立即生效且不需要重新登录。

这些是纯客户端设置，后端不需要额外配置，也不会改变服务器时区。区别只在壁钟语义：

- 按所选时区计算：今日页与日历的“今天”、日期分组、按天统计、习惯打卡周期、提醒触发时刻、黄历和日期格式化。
- 仍按真实瞬时：同步 `updatedAt`、token 过期时间、计时器已流逝时长、番茄钟会话起点。
- 只存年/月/日的浮动日期（待办 `date`、纪念日）不因换时区发生日期平移。

验证时可把时区切到 `Asia/Tokyo`，在服务器仍处于前一天（例如 America/New_York 的 10 月 18 日）时，今日页与万年历应显示次日（10 月 19 日）。完整规则见 [configuration.md](configuration.md#语言与应用时区)。

## 现有服务器

打开 <https://todo.skydrow.site/>，在“我的 → 登录”使用自建服务器账号；管理员登录后向下滚动，进入“管理员后台”。

服务器当前运行的后端与 Web 包不会因修改本地源码而自动更新。后续应将新配置模块、公开 profile、版本元数据和构建产物一起按发布流程部署；保留 `/opt/duoyi/data`、原 bootstrap 用户名和原密码 salt。已有数据库设置继续生效，不需要重新初始化数据库。
