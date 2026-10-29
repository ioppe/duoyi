应用界面统一使用 **Resource Han Rounded CN Bold（资源圆体）**，覆盖简体中文、中英文标点、拉丁字母及数字。它是一份静态 700 字重字库；`pubspec.yaml` 将同一资源按 400 / 500 / 600 / 700 注册，让现有 Regular / Medium / Strong 语义令牌统一呈现圆润粗体字形。

- 上游：Resource Han Rounded CN（资源圆体）发布包，未经修改。
- 文件：`ResourceHanRoundedCN-Bold.ttf`，13,978,508 字节，OS/2 权重 700。
- SHA-256：`f713907a21a10701cd68a7ce3e345ccdce46c789e1809d65ace54e095d7107c3`。
- 授权：[SIL Open Font License 1.1](ResourceHanRounded-OFL.txt)，随应用一起打包。

界面入口统一在 `lib/core/design_tokens.dart`：

- `DesignTokens.fontFamily`：全局字体家族，所有品牌与共享控件继承它。
- `DesignTokens.fontWeightRegular` (400)：正文、说明文字、输入提示、菜单项。
- `DesignTokens.fontWeightMedium` (500)：按钮文字、导航标签、chip、浮动标签。
- `DesignTokens.fontWeightStrong` (600)：页面 / 卡片 / AppBar 标题与强调文字。

字号统一走共享 `DesignTokens.fontSize*` 档位（正文 14、次级 12、说明 11、页标题 18 等）。原生 Android 另以 `DesignTokens.androidFontSizeBody = 12` 在根部 `AppTypography` 应用 12/14 平台基准，标准 100% 默认正文有效字号为 12，其他角色按原层级同比缩放；Web（包括安卓浏览器）、iOS 和桌面保留共享基准。不要在页面里硬编码字号、字重或家族。默认应用比例为 100%，已保存比例保持不变；平台字阶、用户比例与系统缩放分别组合，预览不重复应用平台基准。罕见字符、其他语言和 emoji 仍由 `ThemeData.fontFamilyFallback` 中的系统字体回退处理。

## 兼容字体

`NotoSansSC-Variable.ttf` 与 `NotoSansSC-OFL.txt` 保留在资源目录中，作为历史构建/截图兼容资产，但不再注册为应用 UI 字体。`DroidSansFallbackFull.ttf` 仍用于 PDF 报告，导出字体处理与应用界面独立。
