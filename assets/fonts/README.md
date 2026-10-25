# 应用界面字体

应用界面统一使用 **Noto Sans SC（思源黑体同源的中文无衬线体）** 变量字库，覆盖简体中文、中英文标点、拉丁字母及数字。普通正文为 Regular 400，标签 / 按钮 / 导航为 Medium 500，标题与强调为 Semibold 600。

- 上游：Google Fonts 官方分发的 Noto Sans SC 变量字体（`NotoSansSC[wght].ttf`），经官方 HTTPS 下载，未经修改。
- 文件：`NotoSansSC-Variable.ttf`，17,772,300 字节，变量轴 `wght` 100–900（默认 100），31,036 个字形。
- SHA-256：`a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`。
- 授权：[SIL Open Font License 1.1](NotoSansSC-OFL.txt)，随应用一起打包。

`pubspec.yaml` 把同一个变量文件按 400 / 500 / 600 / 700 四档注册为 `NotoSansSC`，引擎按请求字重选择该资源并应用 `wght` 变体；`assets/fonts/` 整目录仍作为普通资源打包。

界面入口统一在 `lib/core/design_tokens.dart`：

- `DesignTokens.fontFamily`：全局字体家族，所有品牌与共享控件继承它。
- `DesignTokens.fontWeightRegular` (400)：正文、说明文字、输入提示、菜单项。
- `DesignTokens.fontWeightMedium` (500)：按钮文字、导航标签、chip、浮动标签。
- `DesignTokens.fontWeightStrong` (600)：页面 / 卡片 / AppBar 标题与强调文字。

字号统一走较紧凑的 `DesignTokens.fontSize*` 档位（应用标准 100% 时正文 14、次级 12、说明 11、页标题 18 等），不要在页面里硬编码字号、字重或家族。默认应用比例为 100%，用户已保存的比例保持不变；基础字阶变小与用户比例设置分别管理。系统未安装的罕见字符、其他语言和 emoji 仍由 `ThemeData.fontFamilyFallback` 中的系统字体回退处理。

## 旧字库

`ResourceHanRoundedCN-Bold.ttf`（资源圆体 CN Bold，700，13,978,508 字节，SHA-256 `f713907a21a10701cd68a7ce3e345ccdce46c789e1809d65ace54e095d7107c3`，授权见 `ResourceHanRounded-OFL.txt`）是此前的全粗体界面字体，现已不再被界面引用，仅作为历史资源保留打包，以免移除资产影响既有构建与截图证据。新代码不得再引用 `ResourceHanRounded`。

`DroidSansFallbackFull.ttf` 仍用于 PDF 报告，导出字体处理与应用界面独立。
