# 字号设置预览证据

对应版本 `1.1.47+140013`。图片由真实 Flutter `TextSizeSettingsScreen` 的组件测试生成，加载随应用提供的 Noto Sans SC 和 Material Icons 字体，使用默认主题。不是安卓真机截图；实机冷启动、换账号和覆盖安装仍需安装后复查。

- [85% 小号](text-size-85.png)：390×844 逻辑尺寸，2 倍像素输出。
- [100% 标准](text-size-100.png)：标准位于第二刻度。
- [190% 最大字号](text-size-190.png)：拖动只更新预览，“完成”才保存。
- [320px 窄屏 + 系统 200% + 应用 190%](text-size-narrow-system-200.png)：预览已滚动，底部滑块与完成按钮仍可触达。
- [并排查看](index.html)。

生成方式（项目根目录；SDK 版本见 `config/toolchain.json`）：

```bash
DUOYI_TEXT_SCALE_SCREENSHOTS="$PI_SCRATCH_DIR/text-size-v147-captures" \
  "$FLUTTER_BIN" test --no-pub --reporter expanded \
  test/screens/text_size_settings_screen_test.dart
```

默认测试不写截图文件，只有显式设置输出目录才生成图片。组件测试覆盖刻度点击、预览缩放、返回取消、完成保存、重入恢复、换账号草稿失效、保存失败重试与窄屏布局。
