# 清单收纳选择器验证证据

截图来自 Flutter 3.44.1 的实际 release Web 输出，不是 HTML 产品原型。画廊 HTML 仅用于展示 PNG。临时 FastAPI/SQLite 实例和独立 `picker_verify` 账号置于 session scratch，初始有 80 个空自定义清单；不修改已有预览账号的数据。

## 截图

1. `01-desktop-collapsed.png`：1440×1000，表单默认仅显示当前清单一行。
2. `02-desktop-expanded.png`：1440×1000，展开后搜索、三列内置网格和有界纵向清单。
3. `03-desktop-search-last.png`：直接搜索第 80 个清单。
4. `04-mobile-selected.png`：390×844，选择后收起。
5. `05-mobile-expanded.png`：390×844，两列内置网格与纵向浏览。
6. `06-mobile-manage-menu.png`：可见“更多”菜单，包含重命名和删除。
7. `07-mobile-inline-rename.png`：同一面板内修改名称。
8. `08-mobile-inline-error.png`：空名称校验紧贴字段显示。
9. `09-mobile-created-selected.png`：新建“会议筹备”后选中并收起。
10. `10-mobile-320-expanded.png`：320×844 窄屏展开状态。

## 执行结果

- 79 个 picker、共享任务创建表单、Today/Mine 交互测试通过。
- 91 个 provider/sync/i18n/modal/样式检查全部通过。其中 `todo_filters_static_test.dart` 的旧横向 chip 断言按新组件迁移，保留浅色选中背景、文字/勾选反馈约束并新增有界纵向列表要求；迁移后 6/6 复验通过。
- 补验快速创建入口、全局标识与 API 路由静态守卫共 18 项通过；累计 188 为去重后的用例总数。
- 新增账号/服务器切换时丢弃旧清单草稿、编辑器/菜单打开后撤销权限、键盘弹出时展开搜索与选择回归。
- `flutter analyze`：No issues found。
- `flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn`：成功。
- 浏览器真实操作验证：搜索第 80 项、点击选择收起、新建和名称校验、重命名、删除未引用空清单、创建带清单的任务；浏览器脚本错误为空。
- 临时库核对：重命名保留原 ID，删除产生 tombstone，新建清单 ID 与任务的 `listGroupId` 一致，任务 `listGroupName` 一致。最终共 81 条清单注册记录（含一个删除标记）。夹具初始版本使用固定旧时间，以免测试初始化版本比客户端修改版本更新。
- 未重跑完整 Flutter 或后端套件。本次未修改后端或同步协议。

本次验证并由本地 18655 服务的 `main.dart.js` SHA-256：`82f88424013e79f85c631d03a3e4b0d3932a7b3fe585addb486abea371c09564`。构建来自独立 ASCII 验证副本；仓库内 `build/` 可能被其它并行构建更新。

本地 `http://127.0.0.1:18655` 仅更新前端静态文件。更新前验证服务响应与既有挂载目录一致，更新后验证 HTTP 返回 JS 与新 release 构建逐字节一致。没有重启既有后端，没有部署生产服务。

设计和数据语义见 [设计说明](../../../docs/list-group-picker.md)。
