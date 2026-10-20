# 统一登录与注册实测

这些截图来自本次修改后的实际 Flutter Web 构建和原生 Flutter 组件测试，不是 HTML 预览。

## Web

- `01-login-web-1440.png`：1440×1000 桌面登录页，英文系统环境。
- `02-register-web-1440.png`：桌面注册页，沿用同一表单框架。
- `03-login-phone-390.png`：390×844 手机宽度登录页。
- `04-register-phone-390.png`：390×844 手机宽度注册页，长表单可以滚动。
- Web 构建 SHA-256：`d8f14ec197f743cd0f7e6abe8e4efe36acf22fc380235c3334428012e58df51c`

## Android 风格组件

- `11-native-login-390.png`：Android 平台主题的 390×844 登录组件。
- `12-native-register-390.png`：Android 平台主题的 390×844 注册组件。
- `13-native-login-320-large.png`：320×800、1.5 倍字体登录组件。
- `14-native-login-dark-390.png`：深色品牌主题登录组件。

原生截图使用 `ThemeData.platform = TargetPlatform.android`、资源圆体和实际 Material 表单渲染生成；对应的隔离组件检查最终 `1` 项通过。

## 账号流程

在隔离的临时 SQLite 安装中读取本地 `0600` 初始凭据文件，使用 `admin` 登录 Web，确认“我的”显示 `admin @admin 管理员`，并从“我的 → 设置”打开管理员后台。随后退出并通过实际注册页创建普通账号 `auth_verification_user`，确认其“我的”页显示实际用户名、没有管理员标记和管理员后台入口。

临时账号、数据库、凭据文件和浏览器会话在验证结束后清理；本目录不包含任何密码或令牌。
