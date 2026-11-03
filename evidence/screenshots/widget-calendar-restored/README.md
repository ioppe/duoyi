# 月历单月尺寸恢复

本轮仅纠正小组件月历被误改为纵向月份列表、压缩单月正文的问题。用户要求保持原单月大小并左右滑动切月；已完成原单月布局恢复，**左右手势切月尚未实现**，不能将这份尺寸验收视为完整需求通过。

## 当前结果

- 撤下月历纵向列表，顶部恢复月份标题，独立星期行与完整 4–6 周日期网格恢复原来的区域。
- 当前稳定设备截图：[`calendar-stable-final.png`](calendar-stable-final.png)；裁剪图：[`calendar-stable-final-crop.png`](calendar-stable-final-crop.png)。
- 机器证据：[`verification.json`](verification.json)，`all_comparison_bounds_equal=true`，31 个日期各一次，4 个底栏标签，Launcher 前台，无应用 ANR。
- APK 为 Debug ARM64，版本 `1.1.54+140020`，202,224,057 bytes，SHA256 `b810b516b38e45841dd36ddbe3fa3c0d4539a3cd5dc0f8713fd37da1064e8af9`；设备安装的 `base.apk` 摘要一致。

## 与原单月布局的边界对照

| 区域 | 原布局 bounds（px） | 当前 bounds（px） |
| --- | --- | --- |
| 组件 | `[64,466,767,1032]` | `[64,466,767,1032]` |
| 月份标题 | `[164,503,607,555]` | `[164,503,607,555]` |
| 星期行 | `[97,571,734,605]` | `[97,571,734,605]` |
| 日期网格 | `[97,611,734,905]` | `[97,611,734,905]` |
| 底栏 | `[97,922,734,999]` | `[97,922,734,999]` |

设备为 API 35 ARM64 Pixel 5 模拟器、density 2.75；物理实例 ID2 待办宿主与 ID3 专注详细宿主保留。参考为同一设备此前 `widget-apple-design` 单月布局的 AX 记录。这里只证明该尺寸下的布局恢复，不扩大为所有 ROM、所有尺寸或真机结论。

## 检查

- 4 套 Flutter 预览回归共 17 个真实用例通过；其中改写后的月历结构用例单独随 5 个滚动/控制用例再次通过。无效的未命中拖动断言已移除，不作为手势证据。
- Android 资源守卫 41/41 通过；相关 Dart 分析无问题；格式与 diff 检查通过。
- 当前 Debug APK 构建通过，构建前后 16 个相关源文件/资源哈希一致。
- 待办和专注的 Provider、共享导航/集合服务、Dart 控制服务及版本文件与本轮开始时哈希一致。未提交、推送、发布或升版本。

## 未完成项与失败观察

当前标准 Android RemoteViews 可用控件中没有水平手势分页容器。AOSP 的 `StackView` 只按 deltaY 翻页；`Gallery`、`HorizontalScrollView` 没有 `@RemoteView`；`AdapterViewFlipper` 可以满幅换内容但没有左右滑动处理。旋转 `StackView` 会引入卡堆的缩小、透视偏移和裁剪，不能保证本需求的原单月外观。未新增箭头、悬浮层或修改桌面宿主来替代用户要求。

早期 `calendar-restored.png` 属旧包，星期行曾偏移 1px；`calendar-restored-final.png` 在 Launcher 更新的过渡时刻抓到待办，**均不计入通过证据**。最终只读补采集 `calendar-stable-final` 未再次安装、启动、点击或重放输入，已通过原尺寸全部比较。`verification.json` 对应这次稳定采集，保留 `horizontal_swipe_implemented=false`。
