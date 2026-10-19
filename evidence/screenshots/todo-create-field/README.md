# 新建任务输入框高度

“新建任务”底部弹窗的主输入框此前只有约 30px 高，明显小于账号表单。

## 原因

该弹窗外层只套了 `AppSecondaryControlTheme`（紧凑控件档：`isDense: true`、`contentPadding: 10/8`），
标题 `TextField` 直接继承了这一档的内边距，所以在大屏弹窗里显得过小。

## 改动

`lib/screens/todo_screen.dart` 的新建任务输入框改为套 `AppFormFieldTheme`，
即账号表单同一套标准：`isDense: false`、最小高度 `DesignTokens.formFieldMinHeight = 56`、
`contentPadding: spaceLg (16)`、字号 16。弹窗其余控件（清单类型、优先级、提醒）保持原有紧凑档不变。

## 验证

- 真实浏览器（`build/web` release 产物，`http://127.0.0.1:18655/`）实测同一输入框：
  - 改动前：**30px** 高
  - 改动后：**62px** 高（含边框），字号 16px
- 新增 `test/widgets/todo_create_field_height_test.dart`：
  - 标准宽度下高度 ≥ `formFieldMinHeight`
  - 320 宽度下不溢出且保持高度
  - 1.3 倍字体下不溢出
  - 该测试在旧实现（不套 `AppFormFieldTheme`）下 3 项全部失败，改动后全部通过
- `flutter analyze --no-pub`：0 issues
- 静态守卫套件 + 本测试：**336 通过 / 1 失败**，唯一失败是既有基线
  `test/screens/todo_batch_static_test.dart:122`（缩进断言，与本次改动无关）

[桌面截图](new-task-field-desktop.png)
