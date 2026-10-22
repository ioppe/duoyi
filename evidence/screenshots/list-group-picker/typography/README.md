# 清单摘要字号对齐

选择保留清单框体、增大清单名称文字的方案：`todo_list_group_selected_name` 从紧凑的 `labelLarge` 改为 `bodyLarge`，使用 `DesignTokens.fontSizeMd`（16px）和 1.5 行高，与任务名和子任务输入的 `AppFormFieldTheme` 标准一致。继续继承 ResourceHanRounded 粗体和主题颜色。

仅改变收起摘要的文字；56px 最小高度、内边距、图标和点击区域不变。展开后的搜索、选项和管理流程保持原样。长名称可显示两行，并可随文字缩放自然增高。

- `01-before-desktop.png` / `02-after-desktop.png`：1440×1000，使用相同“准备英文会议 / 确认会议安排 / 个人”草稿，旧包与新包实际对比。
- `03-after-mobile.png`：390×844。
- `04-after-320.png`：320×844。

验证：现有 6 个相关测试文件共 **56 项通过**，包含窄屏、1.8 倍文字和键盘场景；`flutter analyze` 无问题；Flutter 3.44.1 release Web 构建成功；实际浏览器脚本错误为空。本轮未重跑完整 Flutter 或后端套件。

修改后截图使用全新浏览器会话加载，避开旧资源缓存。桌面两图的像素差异范围为 `(424,721)–(455,736)`，只覆盖“个人”清单文字区域，其余画面一致。

截图使用独立临时账号和数据库。没有向已有账号写入任务。18655 本地预览仅替换静态前端，更新前后核对 HTTP 返回的 `main.dart.js` 与挂载目录/新构建字节一致；不重启后端，不部署生产环境。

新构建 `main.dart.js` SHA-256：`930dd38da580cda0c153ee4fc2bd2fb1ea74768e80d2a148734ea029c734bff0`。

[实际截图对比](index.html) · [设计说明](../../../../docs/list-group-picker.md)
