# 小组件透明底橙色矢量 logo

2026-10-26，本地调试迭代；版本保持 `1.1.54+140020`。已覆盖安装到官方 Android 模拟器，未提交、推送或发布正式签名包。

## 结果

使用橙色主品牌图案的“日历＋时钟勾选”识别轮廓，整理为适合小组件尺寸的矢量标记。前景固定品牌橙色 `#F28A32`，背景完全透明，直接透出当前卡片底色或背景图片；去掉旧蓝色 Flutter 图和白色方形底。

- 可编辑 SVG：[duoyi_widget_mark.svg](../../../assets/logo/duoyi_widget_mark.svg)。
- Android：`android/app/src/main/res/drawable/duoyi_widget_logo.xml`，原生 VectorDrawable，保持既有资源名和控件 ID；旧同名 nodpi PNG 已从编译目录移除并备份。
- Flutter 组件预览：`WidgetBrandLogo` 通过 CustomPainter 绘制同样的 24×24 轮廓，无新增依赖；无障碍名称使用运行时已有的“多仪 / Duoyi”词条。
- 13 个原生布局的资源引用和点击绑定继续有效。主程序启动图标、Web 与 iOS 原生图标沿用现有配置。

## 实际模拟器核验

官方 API 35 ARM64 Pixel 5 / Apple M3 GPU，系统字体比例 1.0、密度 2.75。使用同一张 3×2 桌面实例，根边界 `[64,466]–[767,1032]`，即 **703×566px**；logo 保持原有 **20dp / 55px** 高度，底栏各标签保持 77px。

| 检查项 | 修改前 | 修改后 |
| --- | ---: | ---: |
| logo 正方形区域白色像素 | 2444 | 0 |
| logo 区域蓝色像素 | 568 | 0 |
| 品牌橙色实心像素 | 0 | 895 |

像素统计基于相同 55×55px 区域与相同阈值。新 logo 内部透明位置和旁边卡片背景的 RGB 均为 **(225,221,222)**，验证了背景连续性。待办页与月历页均通过该检查，无障碍名称仍为“多仪”。月历 31 个日期完整保留；待办 → 日历 → 待办在同一实例内完成，Launcher 保持前台。旧实例 ID 2、3 及其物理 Provider 绑定保留，未发现应用 ANR 或崩溃事件。

已目视检查原生截图。另用 SVG 在浅色、深色和渐变背景上检查透明效果；这些资源预览不代替所有原生主题的设备验收。

## 截图

- [前后对照](index.html)
- [修改前的待办卡](before-todo-logo.png)
- [修改后的待办卡](after-todo-logo.png)
- [修改后的月历卡](after-calendar-logo.png)

## 检查与构建

本轮实际运行 7 个 Flutter 套件、**73 项用例全部通过，0 失败、0 跳过、0 错误**：Android 资源 40、原组件预览 2、完整月历预览 5、组件目录 3、品牌导航 9、iOS 资源 10、l10n 4。`dart analyze --fatal-infos` 无问题；3 个改动 Dart 文件格式检查为 0 改动；`git diff --check` 通过。

固定 Flutter 3.44.1 / Dart 3.12.1 / JDK 17，使用配置包装脚本执行：

```bash
python3 scripts/flutter_with_config.py build apk --debug --target-platform android-arm64 --no-pub
```

2026-10-26 16:30:23Z–16:30:46Z，退出码 0。APK 的资源表和编译后 XML 确认 `duoyi_widget_logo` 是原生 vector，填充透明、描边为品牌橙色，包内不存在旧同名 PNG；SVG 源和 Flutter 矢量绘制代码也已进入产物。

- APK：`build/app/outputs/flutter-apk/app-debug.apk`，**202,175,575 字节**。
- SHA-256：`36dcfd97829f5b80c659e368e43098648f0f385ba793369acb8e7542dc4b0a1a`。
- 包名 `com.duoyi.duoyi`，版本 `1.1.54+140020`，debuggable、target SDK 36，Flutter 引擎为 ARM64。
- 设备安装的 `base.apk` SHA-256 与构建包完全一致。
- 构建前后 50 项源码/资源状态一致（含旧 PNG 为 ABSENT）；既有字体 12、完整月历统计、原生切页及主程序图标资源保持不变。

## 范围

本轮验证覆盖官方 API 35 Launcher 的待办/月历页面及应用内预览相关测试，没有进行真机或正式签名发布。API 31+ 系统选择器的 `previewLayout` 使用新矢量资源；API 30 及更旧启动器读取的 `previewImage` PNG 缩略图沿用既有资源。

机器可读结果见 [verification.json](verification.json)。
