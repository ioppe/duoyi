# 多仪应用 Logo 约定

## 用户确认的图样

所有客户端统一使用下图所示的**红色圆角方块 + 白色三块几何标志**。除用户明确要求更换设计外，版本更新、平台移植、主题切换和构建脚本调整都必须保留这一图样。

![用户确认的 Logo 原图](../assets/logo/duoyi_logo_reference.png)

原始参考图保存在 `assets/logo/duoyi_logo_reference.png`，114×120，保留原图片及色彩配置；SHA-256 为 `4c3121a2a4612a9753c5175ce1ddd32bcbc8f6cd90f1a1cb69a7972d6dd41c8b`。它是用户确认记录，不作为放大的发布图直接使用。

参考图的页面边距不属于标志。红色方块区域为 88×88，取自原图 `(17,12)` 至 `(105,100)`。转换为 sRGB 后，固定品牌红为 **`#C85656`**，图形为 **`#FFFFFF`**；需要不透明画布的平台使用 **`#F6F7F9`** 衬底。不得直接把带色彩配置截图的原始 RGB 数值当作 sRGB 品牌色。

白色轮廓与原登录页 `space_dashboard_rounded` 标志一致，包含左侧长竖块、右上短块和右下竖块。发布母版固定该轮廓，不依赖运行时图标字体、主题主色或主题的 onPrimary 色来改变应用标志。

## 唯一来源

- **可编辑矢量母版**：`assets/logo/duoyi_app_logo.svg`。
- **统一打包源图**：`assets/logo/duoyi_app_logo_1024.png`，由母版生成，1024×1024，不透明 RGB；iOS 的 1024 图标与其字节一致。macOS 从同一母版另行生成透明圆角外缘，不复用这张不透明画布。
- **Android 自适应前景**：`assets/logo/duoyi_app_logo_foreground_1024.png`，由同一母版派生，角落透明；背景为 `#C85656`。
- **原始校对参考**：`assets/logo/duoyi_logo_reference.png`，不参与修改和重新渲染。

`assets/logo/duoyi_logo_redesign_1024.png` 是旧日历插画，`duoyi_logo.svg`、`duoyi_logo_1024.png`、`duoyi_logo_512.png`、`duoyi_logo_192.png` 是旧沙漏资源。它们不代表当前批准的 Logo，不能因为文件名相似或历史配置引用就重新启用。历史截图与发布证据不追溯改图。

## 各端资源映射

| 入口 | 资源/配置 | 维护规则 |
| --- | --- | --- |
| Android 常规启动图标 | `android/app/src/main/res/mipmap-*/ic_launcher.png` | 按密度从统一源图生成 |
| Android 自适应图标 | `drawable-*/ic_launcher_foreground.png`、`mipmap-anydpi-v26/ic_launcher.xml`、`values/colors.xml` | 同一前景轮廓，透明角落，红色背景；保留系统要求的裁剪/安全区 |
| 图标生成配置 | `pubspec.yaml` 的 `image_path` / `adaptive_icon_foreground` | 只指向新的统一源图与自适应前景 |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | 全部声明尺寸来自统一源图；iOS 当前为脚手架目标，资源一致不代表已完成签名发布 |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` | 全部声明尺寸从同一母版生成 RGBA；红色圆角外保持透明，不烘焙浅色画布或白色描边 |
| Linux | `linux/duoyi.png` | 512×512，保持既有应用身份和桌面资源引用 |
| Web 标签页 | `web/favicon.svg`（优先）、`web/favicon.png`（32×32 兼容回退） | 同一母版派生，圆角外必须透明，不能烘焙浅色方底；SVG 保持矢量轮廓 |
| Web/PWA 安装图标 | `web/icons/Icon-*.png`、`web/icons/Icon-maskable-*.png` | 按平台需求保留既有不透明画布与安全区，与标签页 favicon 分开生成 |
| 应用内登录/注册标志 | `lib/widgets/auth_page_frame.dart` | 显示统一图片，保留既有尺寸、圆角和布局，不随主题换图或重新着色 |

各平台可以按系统规范缩放、裁剪和留安全区，但不能改成日历、沙漏、渐变插画或另一套几何图案。通知状态栏等系统功能图标与应用身份图标分别遵守其平台规则。以后新增平台时也必须从本母版生成，不另选默认模板图标。

### macOS Dock 与 Finder

macOS 的 16 / 32 / 64 / 128 / 256 / 512 / 1024 像素 AppIcon 都从母版的红色圆角块和白色路径渲染到透明画布，不能直接复制 iOS 的不透明 1024 图片。抗锯齿应对透明背景计算，不能先铺浅色底再扣色，以免深色 Dock 上出现浅色边缘；白色几何标志保持不透明。

生成器和测试分别核对各尺寸 RGBA、四角透明、品牌色及轮廓；iOS、Android、Linux、Web/PWA 和应用内源图继续遵守各自既有画布规则。用新应用包覆盖更新并重新打开后检查 Dock / Finder，资源检查不能代替已安装应用的实际显示结果。

### 浏览器明暗主题与 favicon

标签页优先声明 `image/svg+xml`、`sizes="any"` 的 `favicon.svg`；为不支持 SVG favicon 的浏览器保留透明 RGBA PNG 回退，SVG 声明排在 PNG 后。两者都从本母版去掉最外层衬底派生，而不是重新设计或对不透明缩略图简单扣色。PNG 回退 URL 带格式修订标识，避免继续使用旧的 16×16 不透明图标缓存。

固定品牌红 `#C85656` 和白色标志不随主题改色。圆角外透明区域直接露出浏览器自己的标签页底色，因此明暗背景都不会出现浅色方框；SVG 本身并不自动保证透明，不能把不透明背景矩形重新加回。网页不能控制所有桌面浏览器的标签栏颜色，`theme-color`/PWA 启动背景也不等同于 favicon 背景，本规则不改这些浏览器或平台设置。

校验 favicon 时同时检查 SVG 不含位图嵌入和最外层衬底、与母版的红块及白色路径同源、PNG 四角透明，并在浅色与深色背景上检查边缘。原生、PWA 安装图标和认证页资源保持各自既有尺寸与规范。

## 生成与校验

本次生成环境为 Pillow 11.3.0、fontTools 4.59.2；重生成或跨机器比对时沿用该环境，避免把光栅化依赖差异误当作批准图样变化。

`scripts/sync_app_icons.py` 是权威生成入口。`pubspec.yaml` 保留的 `flutter_launcher_icons` 配置用于明确来源和兼容工程，不能用 `dart run flutter_launcher_icons` 代替本脚本；其他生成器可能覆盖自适应图标的 inset 或改变重采样，产生的改动需用本脚本重新生成并校验。现有 Flutter Logo 测试会随全量套件核对批准的 SVG 色彩/方向参数与打包图样，完整派生像素检查仍需发布前执行 `--check`。

先激活 Python 3 虚拟环境，再从项目根目录安装固定依赖并执行：

```bash
python3 -m pip install -r scripts/requirements-icons.txt
python3 scripts/sync_app_icons.py
python3 scripts/sync_app_icons.py --check
flutter test --no-pub test/services/platform_logo_assets_test.dart --reporter expanded
```

生成脚本负责母版到各平台产物的同步；`--check` 只校验，不修复或写入文件，发现不一致必须返回非零。不要单独编辑某个平台的 PNG。测试同时核对批准图样的颜色/几何身份、当前源图引用、1024 资源一致性及声明尺寸，避免再次把所有平台统一到错误的图片。

修改后检查 Android 普通/自适应入口、macOS Dock/Finder、Linux 桌面入口、Web favicon/PWA 及登录页展示；按实际可用设备记录检查结果。重新生成资源不等于已安装的客户端或浏览器图标缓存已经更新，旧安装包需要覆盖更新才能取得新资源。

Logo 修改不得更改 `applicationId`、Bundle ID、Linux application id/二进制名或 Web origin；应用身份与用户配置保留规则见 [配置、登录会话与部署隔离](configuration-persistence.md)。
