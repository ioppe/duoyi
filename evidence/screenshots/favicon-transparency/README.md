# 浏览器 favicon 矢量与透明背景修复

## 原因与修复

原网页只声明 16×16 RGB PNG favicon，并沿用原生打包图的 `#F6F7F9` 不透明画布。因此在高像素密度屏幕上不够清晰，深色标签页还会露出浅色方底。

现在优先使用 `web/favicon.svg`（`image/svg+xml`、`sizes="any"`）；它由同一批准母版去掉最外层画布派生，只保留红色圆角块与白色矢量路径。32×32 RGBA PNG 作为兼容回退，四角透明，回退 URL 加格式修订标识避免旧缓存。SVG 声明在 PNG 后，支持 SVG favicon 的浏览器可采用矢量资源。

Logo 红白固定，不因浏览器主题变色。透明外侧露出标签页自己的底色；网页不能强制控制所有桌面浏览器的标签栏颜色，`theme-color` 与 PWA 启动背景是不同机制，本次不改它们。

![旧 PNG 与新透明 SVG/PNG 的浅色和深色背景对照](light-dark-comparison.jpg)

此图为浏览器渲染的资源对照页，不是浏览器原生标签栏截图。深色区域可以复现旧图的浅色方框，新资源不再包含该底色。

## 检查结果

- `python3 scripts/sync_app_icons.py --check`：退出 0，47 个文件匹配，含新增 SVG 与透明 PNG。
- 两个相关 Flutter suite：8/8 通过、0 失败、0 跳过；包括 favicon 同源矢量结构、HTML 声明顺序、PNG alpha/颜色/白块及既有平台资源约束。
- 全项目 `dart analyze --fatal-infos`：退出 0，0 问题。
- 测试文件只读格式检查与 `git diff --check`：退出 0。
- Web release 构建一次成功；SVG/PNG 与项目源资源字节一致，版本保持 `1.1.47+140013`，启动字体子集与完整字库延迟资源及 OFL 均保留。
- 原生、PWA 安装图标、母版、参考图、应用版本及所检查存储实现共 55 个文件的哈希未变。

详细结果见 [validation.json](validation.json)。开发约定见 [branding.md](../../../docs/branding.md)。本阶段记录本地实现与资源核验；公网发布结果另行记录，不把原生安装图标更新或浏览器原生标签栏 UI 验收混入本结论。
