# Web 访问令牌登录入口

此前 `LoginScreen` 仅在安装端默认展示访问令牌表单，Web 显示密码与邮箱验证码。现已在登录选择条增加“令牌 / Token”，所有平台均可从账号登录切换到访问令牌。

- Web 的令牌表单显示 `Uri.base.origin`，服务器字段只读，并说明固定连接当前站点。
- Web 认证仍使用当前站点的相对 API 路径；安装端服务器地址仍可修改。
- 从邮箱验证码模式进入令牌，再返回账号密码登录时，正确恢复密码模式。
- 继续使用此前放大的表单高度与字号。

验证完成：

- 66 项相关 Flutter 回归通过，涵盖登录、令牌界面、服务器隔离、本地化与样式保护。
- 登录测试分别在原生测试环境和 Chrome Web 环境运行，各 2 项通过，包含 320 宽度、模式切换及两端服务器字段的可编辑/只读检查。
- `flutter analyze`：0 issues。
- `python3 scripts/flutter_with_config.py build web --release --no-pub`：成功。
- 实际浏览器出现 `Password / Email code / Token` 三个选项；用本地临时 PAT 完成账号登录，所有 API 请求均来自当前 origin。
- 临时令牌已撤销，重用返回 401；包含令牌的临时私密文件已移除。
- 格式和 `git diff --check` 通过。

[新版预览](index.html) · [三个登录选项](login-options.png) · [Web 令牌表单](token-form.png)

本地应用预览：<http://127.0.0.1:18655/?preview=web-token-v2>。本次未提交、推送或部署到生产站点。
