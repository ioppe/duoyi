# 应用圆体字体

应用界面统一使用 **资源圆体 CN Bold / Resource Han Rounded CN Bold**，字重 700。它以思源黑体为基础，将笔画端点与转角圆润化，覆盖简体中文、中英文标点、拉丁字母及数字。

- 上游：<https://github.com/CyanoHao/Resource-Han-Rounded>
- 来源版本：[v0.990](https://github.com/CyanoHao/Resource-Han-Rounded/releases/tag/v0.990)，归档 `RHR-CN-0.990.7z`。
- 文件：`ResourceHanRoundedCN-Bold.ttf`，未经修改；13,978,508 字节，31,032 个字形，30,887 个 Unicode 映射。
- SHA-256：`f713907a21a10701cd68a7ce3e345ccdce46c789e1809d65ace54e095d7107c3`。
- 文件内版权：Copyright © 2018—2019 Cyano Hao. Portions © 2014, 2015, 2018 Adobe (<http://www.adobe.com/>).
- 授权：[SIL Open Font License 1.1](ResourceHanRounded-OFL.txt)，随应用一起打包；该许可证文本来自上游当前分发文件，涵盖 Cyano Hao 与 Adobe 的版权声明。

`pubspec.yaml` 将字体注册为 `ResourceHanRounded`，`DesignTokens.fontFamilyRounded` 和 `DesignTokens.fontWeightStrong` 为界面统一入口。所有品牌、一级/二级页面及共享控件继承它；文字层级继续使用原有字号、颜色、间距和行高。保留完整上游 CN 字库，避免只裁剪界面文案导致用户自行输入的汉字缺字；字库之外的罕见字符、其他语言和 emoji 仍由系统回退处理。

字体直接从应用资源加载，无需在线字体服务。原有 `DroidSansFallbackFull.ttf` 仍用于 PDF 报告，其导出字体处理与应用界面独立。
