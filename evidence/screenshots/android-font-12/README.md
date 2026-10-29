# Android 默认正文 12：本地迭代验证

2026-10-26 按用户反馈，将原生 Android 默认正文字号从 10 调整为 12。此为工作区本地调试改动，尚未发布正式安装包；版本暂沿用 `1.1.54+140020`，正式发版时再同步版本与发布记录。

唯一运行行为改动是 `DesignTokens.androidFontSizeBody = 12`。根部 `AppTypography` 继续使用 token 比例 `12/14`，因此各文字层级的基准字号相对上一版同比增大 20%，之后仍交给系统 scaler 处理。共享正文 14、Web（含 Android 浏览器）/iOS/桌面八档、字体家族与字重、间距和触控尺寸保持原有契约。

## 七档对应值

以下为系统字号 100% 时的正文逻辑字号。系统线性或非线性缩放仍按原逻辑叠加。

| 档位 | 55% | 70% | 85% | 100% 默认 | 115% | 130% | 145% |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 正文 | 6.6 | 8.4 | 10.2 | 12 | 13.8 | 15.6 | 17.4 |

默认仍为第四档，左右各三档。原先保存的档位继续保留；本轮没有修改偏好读取、owner 绑定、保存/取消或迁移逻辑。

## 实际验证

- 在固定 Flutter 3.44.1 / Dart 3.12.1 / JDK 17 下，本地 ARM64 调试 APK 构建成功，`assembleDebug` 约 42.9 秒。
- 新 APK SHA-256：`82d4d1a2674a3ad33620894703b8e04f89f36d254695df0e0d97103bfc230af6`。包名 `com.duoyi.duoyi`，versionName `1.1.54`、versionCode `140020`，调试签名，非正式发布包。
- 16 个相关套件均实际加载，130 项可见用例通过，0 失败、0 跳过、0 错误；加载与全局 setup/teardown 不计入用例数。
- `dart analyze --fatal-infos` 无问题；7 个改动 Dart 文件的只读格式检查通过，0 格式改动；`git diff --check` 通过。
- 构建和测试前后源码哈希一致；当前源码与两次验证的记录绑定。
- 已安装到官方 Android 15 / API 35 ARM64、Pixel 5、Apple M3 硬件 GPU 模拟器，恢复调试连接。通过 VM 只读观察到实际 `_AndroidBaselineTextScaler` 实例的 `factor = 0.8571428571428571`，即 `12/14`。
- 本次热重启日志确认 `Restarted application in 15,515ms`；原生界面已显示新字号，调试会话保留。

[原生 App 的 12 基准界面](app-baseline-12.png)

原生端验证范围为新包安装、实际根缩放实例、界面和热重启；未把调试器无法直接读取的编译期常量元数据当作已读取值。字号页七档、默认居中、55%/100%/145% 预览、非线性组合、预览单次叠加、账号与保存/取消行为由相关 Widget 测试验证，本轮未另做原生滑块逐档截图。

## 对应测试与契约

- [排版基准与全部七档](../../../test/core/app_typography_test.dart)
- [字号页预览及保存/取消](../../../test/screens/text_size_settings_screen_test.dart)
- [应用根字号](../../../test/widget_test.dart)
- [搜索正文与高亮字号](../../../test/screens/search_text_scale_test.dart)
- [配置说明](../../../docs/configuration.md)
- [手工回归清单](../../../docs/manual-regression-checklist.md)

本轮未触碰原生桌面小组件/PDF 字号、后端、CI、字体资产与许可证，也没有执行整套发布门禁或真机 ROM/锁屏提醒验收。历史 10 基准的已发布版本与旧截图记录保留原样。
