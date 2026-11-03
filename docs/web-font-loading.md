# Web 首屏字体与后台完整字库

## 启动行为

Web 不再 preload 完整 `NotoSansSC-Variable.ttf`。通过统一入口构建后，`assets/FontManifest.json` 的 `NotoSansSC` 只有一份 `NotoSansSC-Startup.ttf` 注册：覆盖 GB2312 一级常用字、应用中文文案、拉丁字符和常见标点，保留变量字重轴。当前子集原始约 2.1 MB，完整字库原始约 17.7 MB。

CanvasKit 根据 `TextStyle.fontWeight` 设置 `wght`，无需为同一变量文件重复登记 400/500/600/700。应用继续使用 `DesignTokens.fontFamily` 和三档字重令牌；Android/macOS 等原生端的完整离线字体及 pubspec 四档登记不变。

应用首帧后至少等待 15 秒，再在浏览器空闲时加载一次完整字库。页面不可见、离线、开启省流量，或有效网络类型为 2G/slow-2g 时，本会话跳过后台下载。字节加载等待上限为 60 秒；下载/解析失败不影响首屏、登录和业务操作，不弹出错误，不反复重试。

完整字库仍从同源 Flutter asset 加载，浏览器遵循 HTTP 缓存；下载成功后注册到同一 `NotoSansSC` 字体家族并通知文字布局更新，不重建应用或丢弃输入。子集外的字在完整字库尚未就绪时，保留 CanvasKit 的按需字形回退；这可能下载额外的小字库，并不保证任意语言在首次离线时都有字形。不能把 CSS `system-ui` 或 `font-display: swap` 当作 CanvasKit 的零下载中文方案。

## 构建入口

```bash
python3 scripts/flutter_with_config.py build web --release --base-href=/
```

统一入口成功构建 Web 后自动运行 `scripts/prepare_web_fonts.py`：

- 校验完整字体与已提交子集的 SHA-256 和变量轴。
- 仅改写生成的 Web FontManifest，保留图标和其他字体。
- 复制子集与 SIL OFL 许可，生成 `assets/web-font-policy.json` 供部署检查。
- 保留完整字体文件供首帧后的加载器读取。
- 尊重 `--output`/`-o`；非 Web 构建和 dry-run 不做字体后处理。

直接运行 `flutter build web` 不包含这一步；如确需直接构建，发布前必须执行 `python3 scripts/prepare_web_fonts.py <构建目录>`。GitHub Actions 的桌面、移动和 Pages 构建均使用统一入口。

## 更新子集

源完整字体与原生注册不能为减小 Web 首屏而删除。子集是已提交资源，普通 CI 不依赖 FontTools。中文文案或源字体更新后，开发者可用 FontTools 4.59.2 重新生成：

```bash
python3 scripts/generate_web_startup_font.py
```

`assets/fonts/web-startup-font.json` 记录源/子集哈希、字符集、体积和生成器版本。生成过程保留字形度量与变量轴，OFL 许可随构建分发。

## 验证

- 冷启动只请求一次 `NotoSansSC-Startup.ttf`，完整字体不在首屏关键链路。
- Performance marks：`duoyi-font-first-frame`、`duoyi-font-download-start`、`duoyi-font-loaded`，或 `duoyi-font-skipped`/`duoyi-font-error`。
- 完整字体请求晚于首帧至少 15 秒且每会话最多一次；下载期间可切换页面、输入文字，输入不丢失。
- 拦截完整字体请求，确认登录/首屏仍能使用；检查未知汉字回退和正文/按钮/标题字重。
- Web 清单只有一个子集登记；原生完整字体四档仍在，PDF Droid 字体不受影响。
- 自动检查：`backend/test_web_font_build.py`、`test/services/deferred_web_font_service_test.dart`，及原有 typography/static guards。

Nginx/CDN 应对 TTF 使用正确 MIME 与压缩；manifest、bootstrap 和入口不能用长期 immutable 缓存。字库内容不变时可复用字体缓存，不能把旧的四份完整字体清单长期留在 CDN 中。
