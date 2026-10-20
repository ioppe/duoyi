# 认证卡片翻转与登录能力实测

本目录包含最终 Flutter Web 构建截图、实际双向翻转录屏，以及 Android 平台主题的原生 Material 组件渲染。查看 [交互证据页](index.html) 或 [翻转视频](07-card-flip.webm)。

## 最终行为

- Web 不显示令牌登录。默认只显示密码登录；无固定的首次 `admin` 提示，凭据获取写在安装文档中。
- 邮箱验证码登录仅在管理员显式开启、账号邮件服务启用并且实际发送候选渠道配置完整时出现。前端读取公开布尔能力，后端同时拦截发码与消费验证码的全部登录别名。
- 登录与注册卡片等高，480ms 沿纵轴翻面，返回时反向翻回。一次只挂载一份可交互表单；系统减少动画设置下直接切换。
- 主按钮固定在卡片底部，辅助操作在按钮下方同一行；中间表单内容滚动。邮箱/密码切换保留标题、字体、输入框坐标与选择器尺寸，安装端令牌复用同一卡片。

## Web 证据

- `01-web-password-1440.png` / `02-web-register-1440.png`：1440×1000 的等高登录/注册页。
- `03-web-password-390.png` / `04-web-register-390.png`：390×844，主按钮完整显示，长表单内部滚动。
- `05-web-email-enabled-390.png` / `06-web-email-form-390.png`：邮件配置完成后的密码/邮箱切换。
- `07-card-flip.webm`：最终实际构建双向翻转，英文系统环境。

隔离新库默认 `email_code_login_enabled=false`。通过有权限的管理员 API 开启开关但未配邮件时，公开状态仍为 false、页面隐藏入口；补齐隔离测试 SMTP 候选配置后变为 true；关闭开关后再次隐藏。此过程不发送真实邮件。默认 Web 无令牌/邮箱/首次管理员提示。浏览器无错误。

最终构建与隔离服务返回的 `main.dart.js` SHA-256 一致：

`1a0c917d9d52808e7f5c9345016e50af7c5cc14f7a66461be2c7dd24f6af7fb1`

## Android 组件证据

`11-android-password-390.png`、`12-android-email-390.png`、`13-android-token-390.png`、`14-android-register-390.png` 使用同一 `LoginScreen`、资源圆体和 `ThemeData.platform=TargetPlatform.android`。`15-android-large-320.png` 覆盖320px/1.5倍字体，`16-android-dark-390.png` 覆盖深色品牌。隔离原生渲染测试1项通过；不把该证据当作真机APK验收。

## 自动验证

- 后端完整四模块：247项通过。
- 完整 Flutter 回归：1914项通过、2项既有静态断言失败：`todo_batch_static_test.dart` 的源码缩进、`admin_user_status_test.dart` 的旧页签最小宽度。
- 随后固定主按钮后，最终认证/配置/门禁/国际化定向回归115项全部通过；未重跑完整套件。
- 最终 `flutter analyze` 无问题，Web release 构建成功，`git diff --check` 通过。
- 几何测试比较卡片切换前/中/后的边界、翻转矩阵、唯一表单、底部操作同行、主按钮可见性和各登录方式文字样式/输入坐标；覆盖320px、放大字体、九主题和减少动画设置。

所有运行使用隔离数据库。验证后关闭会话、停止临时服务、删除临时数据库及凭据。本目录不含实际密码、访问令牌或邮件密钥；没有修改或部署生产服务。
