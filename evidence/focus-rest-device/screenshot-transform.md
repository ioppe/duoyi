# 真机截图变换

原始 Android 屏幕为 1200×2670 像素，系统密度 520 dpi，系统字号 1.25。原图仅保存在本次会话 scratch 中。

归档图使用 CoreGraphics `CGImage.cropping(to:)` 从原图取矩形 `(x=0, y=160, width=1200, height=2510)`，只移除顶部系统栏区域，输出为 1200×2510；不缩放、不重排、不修改应用内容。该裁切工具对输入和输出尺寸均有断言。原始和归档 PNG 的 SHA-256 记录在 `screenshots.json`。

UIAutomator 节点和输入位置仍使用原始屏幕坐标。映射到归档截图时，`x' = x`、`y' = y - 160`，单位均为物理像素。未进入裁切范围的系统内容不作为产品截图公开。

HTML 设计稿、Flutter widget 渲染图与本目录的物理 Android 屏幕证据分别保存，不能互相替代。
