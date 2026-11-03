# 全平台统一红底白标

2026-10-27，本地实现与验收，版本保持 `1.1.54+140020`。未提交、推送或发布正式签名版本。根据用户参考图重绘统一矢量，保留红色圆角方块、中央白色左柱与右上/右下两块，以及参考图的留白。

## 统一范围

唯一编辑源为 [duoyi_unified_logo.svg](../../../assets/logo/duoyi_unified_logo.svg)，96×96 坐标，品牌红 `#C95455`、白色 `#FFFFFF`。原生小组件矢量与 Flutter `WidgetBrandLogo` 使用 1/4 坐标的同一几何。

- Android：启动图标、自适应前景、小组件和系统预览布局。
- Flutter：小组件预览、登录/注册/找回密码头标、桌面导航侧栏；保持原有尺寸、表单和导航布局，不再单独使用主题色 dashboard 作为品牌标记。
- Web：favicon、192/512 图标、maskable 图标、manifest 品牌颜色及实际登录页。
- iOS：AppIcon 声明的全部尺寸，使用无 alpha 的满底输入。
- Linux：`linux/duoyi.png`，沿用 `.desktop` 的图标名。

`python3 scripts/generate_brand_assets.py` 从同一 SVG 生成 PNG，`--check` 检测漂移。普通标记外围透明；Android 自适应、iOS 和 Web maskable 的外形由系统/浏览器遮罩决定。Android 预测应用位置可能添加系统装饰环，非源图内容。倒计时沙漏、通知小铃铛及不含品牌图案的功能缩略图保留其用途；历史截图、发布记录和备份不回写。

## 实际核验

Android API 35 ARM64 模拟器已覆盖安装最终包。组件与启动图标均显示红底和三个独立白色图形，已通过像素连通域和目视检查。组件根边界仍为 `[64,466]–[767,1032]`，即 703×566px；logo 控件高 55px，旧组件 ID 2、3 保留，无障碍名称为“多仪”。安装 `base.apk` 与最终构建包摘要相同。

`http://localhost:18655/` 已热重启并重新导航，实际登录页显示统一标记。favicon 与四个 PWA 图标的 HTTP 响应逐字节匹配源文件，浏览器像素采样也正确。Flutter run 模式的 manifest 返回开发占位说明；完整 Web 构建产物中的 manifest 与源语义一致，图标摘要一致。

[查看统一图标](index.html) · [最终 Android 桌面](android-final.png) · [最终 Web 登录页](web-login-final.jpg)

## 测试与最终构建

- 派生资源 `--check` 退出码 0，`changed_assets: []`。
- 15 个不同套件的最近一次结果去重后，共 **139 项用例通过，0 失败、0 错误、0 跳过**；覆盖资源、预览、动作桥接、认证流程、注册布局、登录、桌面与主入口。
- `dart analyze --fatal-infos` 无问题，格式检查 0 改动，`git diff --check` 干净。
- 最终 Android：`python3 scripts/flutter_with_config.py build apk --debug --target-platform android-arm64 --no-pub`，2026-10-27 02:54:35Z–02:54:55Z，退出码 0。
- 最终 APK：**202,177,477 字节**；SHA-256 `29fdc815a814f16c4e16f76ffcf515db53942fd65f81e824302220dbe108418a`。包名 `com.duoyi.duoyi`，版本 `1.1.54+140020`、debuggable、target SDK 36、ARM64 引擎，设备安装摘要一致。
- 最终 Web：`python3 scripts/flutter_with_config.py build web --debug --no-pub`，2026-10-27 02:55:03Z–02:55:55Z，退出码 0；manifest、favicon 与图标校验通过。
- 工具链为 Flutter 3.44.1 / Dart 3.12.1 / JDK 17。认证头标、main 和资源测试在最后检查前后的完整摘要保持不变。初次资源报告使用前一轮快照作对照，不将它描述为本轮完整构建前快照。

最初的统一资源检查包摘要为 `05be41d981aae68df1e312cd0fc5f95cff4caf14e341f622d4a84158dabe9ec9`；后续接入认证页和桌面侧栏后已重新测试、重建并安装最终包。最初的组件/启动图标局部截图仍展示相同矢量资源，最终完整桌面和网页登录页另行保存。

iOS、Linux 完成资源生成与静态检查，未进行它们的设备运行验收；Android 使用官方模拟器，未宣称全部手机 ROM 或正式签名验收通过。既有字体、完整月历、每日事项角标、账号和切页逻辑保留。机器摘要见 [verification.json](verification.json)。
