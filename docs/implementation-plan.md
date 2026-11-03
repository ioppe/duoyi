# 多仪实现总计划

本文档把 `docs/task.md` 里的 M2-M15 重新编排成一条可执行路线。原则很简单：

- 先做数据模型，再做调度，再做 UI。
- 先打通本地闭环，再接统计、日历、成就、共享。
- 每一阶段必须有可测的产物，再进入下一阶段。

## 1. 执行顺序

### Phase A: 提醒模型

目标：把单条提醒升级为多条规则。

顺序：

1. M2 多次提醒模型
2. M3 多次提醒调度
3. M4 多次提醒 UI

完成门槛：

- Todo / Goal 能同时持有多条提醒规则。
- 老数据仍可读、仍可写回 legacy 镜像。
- 新提醒编辑器能增删改规则并保存。

### Phase B: 时间足迹

目标：把“做了多久”变成一等数据。

顺序：

1. M5 时间足迹模型与 Provider
2. M6 时间足迹自动记录
3. M7 时间足迹 UI 与统计

完成门槛：

- 专注、待办、习惯、目标都能生成或补记时间记录。
- 今日页 / 统计页 / 日历页都能看到时间足迹。
- 导出和同步能携带时间记录。

### Phase C: 日历枢纽与成就

目标：把跨模块操作收拢到统一入口。

顺序：

1. M8 日历统一详情与跨模块操作
2. M9 课程表、纪念日深化（倒数日恢复可见）
3. M10 成就事件管线

完成门槛：

- 日历事件可跳转、完成、改期、删除。
- 课程 / 纪念日进入统一事件流；倒数日保留可见新增、搜索、日历聚合、导出和深链能力。
- 成就能根据领域事件自动进度更新。

### Phase D: 共享与同步

目标：补齐多人共享和数据收口。

顺序：

1. M11 共享空间后端
2. M12 共享空间前端
3. M13 小组件增强与深链
4. M14 同步、备份、迁移收口

完成门槛：

- workspace、member、invite 全链路可用。
- 共享对象能同步、可控权、可恢复。
- 备份/导出/导入不会丢新增模型。

### Phase E: 发布验收

目标：把功能变成可发版结果。

顺序：

1. M15 发布验收

完成门槛：

- `flutter analyze` 通过。
- `flutter test test/` 通过。
- 真机专项通过。
- 构建包可发布到 GitHub Release。

## 2. 详细拆解

### M2 多次提醒模型

先做的文件：

- `lib/models/goal.dart`
- `lib/models/todo.dart`
- `lib/models/recurrence.dart` 或新建提醒模型文件
- `test/models/*_json_compat_test.dart`

重点：

- 新增 `ReminderRule` / `ReminderPlan`
- 保留 legacy `ReminderConfig`
- 给 `ReminderPlan.fromLegacy(...)` 补兼容路径

### M3 多次提醒调度

先做的文件：

- `lib/services/reminder_scheduler.dart`
- `lib/services/reminder_sinks.dart`
- `test/services/channel_routing_pbt_test.dart`

重点：

- rule 粒度稳定 id
- 单条失败不阻断整轮同步
- push/alarm 双通道清理

### M4 多次提醒 UI

先做的文件：

- `lib/widgets/reminder_plan_editor.dart`（新建）
- `lib/screens/todo_detail_screen.dart`
- `lib/screens/goal_edit_screen.dart`
- `lib/screens/habit_detail_screen.dart`

重点：

- 用统一编辑器替换散落的单条提醒控件
- 支持提前提醒、到期提醒、每日/每周提醒
- 任务详情采用短防抖自动保存，页面继续保留；返回或点击勾号时等待最新修改落盘再退出，不再弹未保存改动确认。

### M5-M7 时间足迹

先做的文件：

- `lib/models/time_entry.dart`
- `lib/providers/time_audit_provider.dart`
- `lib/screens/time_audit_screen.dart`
- `lib/screens/statistics_screen.dart`
- `lib/screens/mine_screen.dart`

重点：

- 持久化、聚合、编辑、删除
- 番茄完成自动写入
- 待办/习惯/目标完成时支持补记

### M8-M10 日历与成就

先做的文件：

- `lib/core/calendar_aggregator.dart`
- `lib/widgets/calendar_event_sheet.dart`
- `lib/screens/calendar_screen.dart`
- `lib/core/achievements.dart`
- `lib/providers/*` 领域事件接入

重点：

- 统一事件和动作路由
- 冲突提示
- 成就规则数据化

### M11-M14 共享与同步

先做的文件：

- `backend/main.py`
- `backend` 数据表与接口
- `lib/models/workspace*.dart`
- `lib/providers/share_provider.dart`
- `lib/services/backup_service.dart`

重点：

- workspace / member / invite 先后端后前端
- 同步 payload 对齐新模型
- 备份导入导出覆盖新增字段

## 3. 验证节奏

每个 phase 结束都要跑：

1. 目标文件的 `flutter analyze`
2. 对应单元 / widget / property test
3. 手工回归清单中相关条目

最后一轮统一补：

- 真机通知验证
- 小米专项验证
- GitHub Release 构建检查

## 4. 当前状态

- M0 已完成
- M1 已完成
- M2 已完成
- M3 已完成
- M4 已完成
- Phase A 已闭环
- Phase B（M5-M7）已完成
- Phase C（M8-M10）已完成
- Phase D（M11-M14）已完成
- Phase E 已完成发布链路：`flutter analyze`、`flutter test`、后端 `unittest`、GitHub Actions Android/Web 构建、`v1.0.8` GitHub Release、应用内 `releases/latest` 更新识别均已验证；小米真机通知仍需在实际设备上手工确认
