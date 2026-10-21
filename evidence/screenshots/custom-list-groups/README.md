# 自定义清单类型（list group）

新建待办里的「清单类型」不再只有内置六个模板，用户可以自己新增、重命名、删除清单，并随 `/api/sync` 多端同步。

## 行为

- chips 数据源 = 内置模板（工作/个人/学习/购物/阅读清单/健身）∪ 自定义清单 ∪ 已有任务里出现过的清单名，按共享空间写权限过滤。
- 「＋ 新建清单」固定在最左侧；点击后就地从 chip 变成输入框（不是弹窗）。
- 输入时下方实时列出最相关的已有清单（开头匹配优先，其次包含匹配），点选即选中已有清单。
- 提交时若与已有清单归一化重名（忽略大小写与首尾空白），直接选中那一条，不会新建重复项；空值与超长仍在原地提示。
- 长按自定义清单可重命名或删除；内置六项只读。删除是墓碑（`isDeleted`），不会批量改写已有任务。
- AI 拆解白名单使用同一并集，因此新清单可以被 AI 建议。
- 同步：按 `id` 合并、`updatedAt` 较新者胜，墓碑同权；新设备登录即拉到全部清单。

## 真实构建验证（本机 18655，Flutter Web release）

1. `03-create-sheet.png`：新建表单底部出现「＋ New list」。
2. `04-new-list-created.png`：输入「旅行」确认后，chip 出现且自动选中。
3. `05-persisted-after-reload.png`：整页刷新后重新打开表单，「旅行」仍在（本地持久化）。
4. 服务端 `sync_data.list_groups` 已自动写入该记录；用空集合模拟全新设备调用 `/api/sync`，返回 `[('旅行', False)]`，即多端同步生效。
5. `06-create-chip-leftmost.png`：「＋ New list」在所有清单 chip 的最左侧。
6. `07-inline-input.png`：点击后原地变成输入框，同时出现确认/取消按钮，没有对话框。
7. `08-inline-suggestions.png`：输入「旅」立即补全出已有清单「旅行」。
8. `09-suggestion-selected.png`：点选建议后直接选中「旅行」，输入框收起。
9. `10-created-new-list.png`：输入新名称「读书」确认后创建并选中。

## 自动化回归

- 后端 165 项通过，新增 `test_sync_round_trips_custom_list_groups_with_lww_and_tombstone`（增删、LWW、墓碑、账号隔离、重读）。
- Flutter 新增 `list_group_provider_test`、`list_group_cloud_sync_test`、新建表单与今日页入口回归；`flutter analyze` 无问题。
- 完整 `flutter test`：2039 通过、5 失败；5 项在 HEAD 上以同样方式失败（`todo_batch_static_test`、`ai_review_markdown_test`、`almanac_screen_test`×2、`admin_user_status_test`），与本次改动无关。

契约见 [cloud-sync-v2-contract.md](../../../docs/cloud-sync-v2-contract.md)，`API_CONTRACT_VERSION` 已升到 `2026-06-01.6`。未部署生产环境。
