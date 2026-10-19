# 底部弹窗阴影/拖动条修复

## 现象

所有底部弹窗（新建任务、日历详情、筛选面板等）在卡片上方还有一条独立的拖动示意按钮，
阴影也比实际卡片更大，卡片与阴影之间存在错位。

## 根因

`lib/core/app_brand.dart` 的 `bottomSheetTheme` 设置了 `showDragHandle: true` 与
`modalElevation: 4`。`showAppModalSheet` 里的 `showModalBottomSheet` 没有覆盖这两项，
于是路由层自己的 Material 额外占了 `kMinInteractiveDimension`（48）高度并画出 Flutter
默认的 32×4 手柄；同时 `AppModalSheet` 内部又画了自己 40×4 的手柄 → **两个手柄 + 两层阴影**。

## 修改

`lib/widgets/surface_components.dart`

1. `showAppModalSheet` 显式传 `showDragHandle: false`、`elevation: 0`、
   `backgroundColor: Colors.transparent`，把拖动条和阴影统一交给 `AppModalSheet`。
2. `AppModalSheet` 的 `SafeArea` 改为 `bottom: false`，卡片真正贴住屏幕底边；
   同时把 `media.padding.bottom` 加进内部 `sheetPadding`，全面屏上内容不会压到手势条。

`lib/screens/todo_screen.dart`

`_showAddDialog` 里 `AppDropdownField<EisenhowerQuadrant>` 删除 `labelText: '优先级'`：
上方已有 `appSecondaryControlLabelStyle` 的分区标题，浮动标签重复显示同一个词。

## 测试

`test/widgets/app_modal_sheet_drag_handle_test.dart`（新增，4 条）

| 用例 | 修复前 |
| --- | --- |
| 底部弹窗只渲染一个拖动手柄（手柄形状容器计数 == 1） | 失败（2 个） |
| 路由层 `showDragHandle`/`elevation`/`backgroundColor` 解析后关闭 | 失败（true / 4） |
| 卡片与 `AppModalSheet` 底边贴合 800 | 通过 |
| 带 34 手势条时仍保留底部安全区留白 | 通过（防回归） |

前两条在修复前实现下实测失败，修复后 4 条全通过。

## 浏览器实测（1280×577，本地预览）

- 沿 `x=640` 扫描像素：唯一手柄出现在 `y=24..28`，颜色 `(228,229,230)`；
  卡片上方 0..24 全是白色，无深色行 → 只剩一个手柄。
- 卡片底边一直延伸到截图最后一行，无错位缝隙。
- 弹窗文本里 `优先级` 出现 2 次，其中一次属于独立分区「优先级标记」，
  浮动标签重复已消失（DOM 中该分区标题行 `y=261`，紧接下拉值 `y=286`）。

截图：`new-task-sheet-before.png`（修复前，卡片上方有深色行）/`new-task-sheet-after.png`（修复后）。

## 验证命令

```bash
flutter analyze --no-pub                    # No issues found
flutter test --no-pub test/widgets/app_modal_sheet_drag_handle_test.dart
flutter test --no-pub test/*/*_static_test.dart   # 333 通过 / 1 基线失败
```
