# 应用界面字体

应用界面统一使用 **Noto Sans SC（思源黑体同源的中文无衬线体）** 变量字库，覆盖简体中文、中英文标点、拉丁字母及数字。普通正文为 Regular 400，标签 / 按钮 / 导航为 Medium 500，标题与强调为 Semibold 600。

- 上游：Google Fonts 官方分发的 Noto Sans SC 变量字体（`NotoSansSC[wght].ttf`），经官方 HTTPS 下载，未经修改。
- 文件：`NotoSansSC-Variable.ttf`，17,772,300 字节，变量轴 `wght` 100–900（默认 100），31,036 个字形。
- SHA-256：`a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`。
- 授权：[SIL Open Font License 1.1](NotoSansSC-OFL.txt)，随应用一起打包。

`pubspec.yaml` 把同一个变量文件按 400 / 500 / 600 / 700 四档注册为 `NotoSansSC`，引擎按请求字重选择该资源并应用 `wght` 变体。PDF 导出字体作为单独普通 asset 保留；不再把整个 `assets/fonts/` 目录打入 Web 资产清单。

Web 发布使用同源变量子集 `NotoSansSC-Startup.ttf`（GB2312 一级常用字、应用中文文案、拉丁字符/标点），仅登记一次；完整字体在首帧后空闲时静默加载，原生四档完整字体保持不变。子集哈希、字符覆盖和生成器版本记录在 `web-startup-font.json`，可用 `python3 scripts/generate_web_startup_font.py`（FontTools 4.59.2）重新生成，许可同上。构建入口、失败回退和验证见 [Web 字体加载](../../docs/web-font-loading.md)。

界面入口统一在 `lib/core/design_tokens.dart`：

- `DesignTokens.fontFamily`：全局字体家族，所有品牌与共享控件继承它。
- `DesignTokens.fontWeightRegular` (400)：正文、说明文字、输入提示、菜单项。
- `DesignTokens.fontWeightMedium` (500)：按钮文字、导航标签、chip、浮动标签。
- `DesignTokens.fontWeightStrong` (600)：页面 / 卡片 / AppBar 标题与强调文字。

字号统一走 `DesignTokens.fontSize*` 档位（正文 16、次级 14、说明 12、页标题 20 等），不要在页面里硬编码字号、字重或家族。原生端的罕见字符、其他语言和 emoji 可使用系统字体回退；Web CanvasKit 使用引擎按需下载的字形回退，不保证首次离线时任意字符都有字形。

## 旧字库

`ResourceHanRoundedCN-Bold.ttf`（资源圆体 CN Bold，700，13,978,508 字节，SHA-256 `f713907a21a10701cd68a7ce3e345ccdce46c789e1809d65ace54e095d7107c3`，授权见 `ResourceHanRounded-OFL.txt`）是此前的全粗体界面字体，现已不再被界面引用，仅作为历史资源保留在仓库中；当前 Flutter Web 构建不再将它打包。新代码不得再引用 `ResourceHanRounded`。

`DroidSansFallbackFull.ttf` 仍用于 PDF 报告，导出字体处理与应用界面独立。
