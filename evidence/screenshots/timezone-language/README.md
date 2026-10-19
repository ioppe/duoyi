# 语言与应用时区

界面语言与应用时区默认跟随系统，用户可显式固定并立即生效。此前“应用时区”只写入偏好、未真正驱动全局日期，“界面语言”也没有跟随系统语义，本次统一收敛到 `AppClock` + `LocalTimezoneResolver` + `LocaleProvider`。

验证完成：

- 完整套件 1713 项通过、静态守卫 333 项通过，仅剩 1 项与本次改动无关的既有失败（`todo_batch_static_test.dart:122` 缩进断言，文件与 HEAD 逐字节一致）。
- `flutter analyze`：0 issues。
- 真实浏览器：系统 `en-US` 时界面为英文；切换简体中文无需刷新即刻生效；应用时区改为 `Asia/Tokyo` 后，今日页与万年历在纽约仍是 10 月 18 日时显示 10 月 19 日。
- 验证结束后已把浏览器偏好恢复为“跟随系统 + 系统时区”。

[简体中文设置页](language-zh-settings.png) · [今日页跟随 Asia/Tokyo](today-asia-tokyo.png) · [验证记录](../../timezone-language/verification.md)

本地应用预览：<http://127.0.0.1:18655/>。本次未提交、推送或部署到生产站点。
