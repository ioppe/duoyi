# 多仪（Duoyi）竞品分析报告

> 基于代码库 v1.0.21 实际能力，对标主流效率工具的功能差距与差异化分析。
>
> 更新日期：2026-05-22

---

## 1. 竞品概览表（功能对比矩阵）

| 功能维度 | 多仪 Duoyi | 滴答清单 TickTick | Todoist | 番茄TODO | Forest | Microsoft To Do |
|---|---|---|---|---|---|---|
| **任务管理** | | | | | | |
| 四象限（Eisenhower） | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 子任务 | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| 优先级 | ✅ 5级 | ✅ 5级 | ✅ 4级(P1-P4) | ✅ | ❌ | ✅ 重要标记 |
| 看板视图 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 自然语言输入 | ✅ 中英文日期解析 | ✅ 智能解析 | ✅ 业界领先 | ❌ | ❌ | ❌ |
| 任务标签 | ✅ | ✅ | ✅ 标签+筛选器 | ✅ | ✅ | ❌ |
| 筛选器/自定义视图 | ✅ 标签/日期/象限/优先级/清单 | ✅ 智能清单 | ✅ Filters | ❌ | ❌ | ❌ |
| 重复任务 | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| 任务顺延/自动滚转 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 时间追踪/时长记录 | ✅ 时间足迹 | ✅ 持续时间 | ❌ | ✅ 时间线 | ❌ | ❌ |
| **日历与日程** | | | | | | |
| 月视图 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 周视图 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 日视图（Agenda） | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 时间线视图 | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| 三日视图 | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 第三方日历订阅 | ⚠️ ICS/CalDAV/OAuth 已接入，真机账号待验 | ✅ Google/Outlook | ✅ Google/Outlook | ❌ | ❌ | ✅ Outlook原生 |
| ICS 导出 | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| 农历/节气 | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **提醒系统** | | | | | | |
| 推送通知 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 闹钟级提醒 | ✅ 全屏+震动 | ✅ | ✅ | ✅ | ❌ | ✅ |
| 多次提醒 | ✅ ReminderPlan | ✅ | ✅ | ❌ | ❌ | ✅ |
| 提醒偏移模板 | ✅ 5/15/30/60分钟+1/2/3天 | ✅ | ✅ | ❌ | ❌ | ✅ |
| 位置提醒 | ✅ 前台/任务关联 | ✅ | ✅ | ❌ | ❌ | ❌ |
| **专注模式** | | | | | | |
| 番茄钟 | ✅ | ✅ | ❌ | ✅ 核心功能 | ✅ | ❌ |
| 白噪音 | ✅ 31条单音轨 | ✅ 10+种 | ❌ | ✅ 30+种 | ❌ | ❌ |
| 白噪音单音轨库 | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| 锁屏/屏蔽干扰 | ✅ Android DND | ❌ | ❌ | ✅ 核心功能 | ✅ 核心功能 | ❌ |
| 自习室/社交专注 | ✅ 本地自习室+排行 | ❌ | ❌ | ✅ | ✅ | ❌ |
| 专注时长自定义 | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| 任务关联专注 | ✅ FocusLink | ✅ | ❌ | ✅ | ❌ | ❌ |
| **习惯追踪** | | | | | | |
| 习惯打卡 | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| 热力图 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 连续天数/最佳连续 | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| 正向+负向习惯 | ✅ | ❌ 仅正向 | ❌ | ❌ 仅正向 | ❌ | ❌ |
| 计量单位（次/杯/分钟） | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 每周目标天数 | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| **目标管理** | | | | | | |
| 独立目标模块 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 目标分类体系 | ✅ 6类 | ❌ | ❌ | ❌ | ❌ | ❌ |
| 调度策略（固定/随机） | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 推荐目标库 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **日记** | | | | | | |
| 心情记录 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 心情热力图 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 日记连续天数 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **笔记** | | | | | | |
| 随手记/便签 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 富文本编辑 | ✅ Markdown 描述/笔记 | ✅ Markdown | ✅ | ❌ | ❌ | ❌ |
| 图片/附件 | ✅ 任务+笔记基础附件 | ✅ | ✅ | ❌ | ❌ | ✅ |
| **统计分析** | | | | | | |
| 任务完成率 | ✅ | ✅ | ✅ Karma分 | ✅ | ❌ | ❌ |
| 专注时长统计 | ✅ | ✅ | ❌ | ✅ 非常详细 | ✅ | ❌ |
| 习惯完成率 | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| 时间审计 | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| 周/月/年维度切换 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 导出报告 | ✅ Markdown/PNG/PDF 多模板 | ✅ | ✅ | ✅ | ❌ | ❌ |
| **协作与共享** | | | | | | |
| 共享空间/清单 | ✅ 空间/清单/日程/目标 | ✅ 成熟 | ✅ 成熟 | ❌ | ❌ | ✅ |
| 任务分配 | ✅ 共享空间负责人 | ✅ | ✅ | ❌ | ❌ | ✅ |
| 评论/讨论 | ✅ 空间+任务评论 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 好友系统 | ✅ 专注好友 | ❌ | ❌ | ✅ | ✅ | ❌ |
| **小组件 Widget** | | | | | | |
| 独立 Widget 类型 | ✅ Android 10种 | ✅ 5+种 | ✅ 3种 | ✅ | ✅ | ✅ |
| 待办列表 Widget | ✅ Top3 + 勾选 | ✅ 完整列表 | ✅ | ✅ | ❌ | ✅ |
| 快捷添加 Widget | ✅ 待办快捷添加 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 多尺寸 Widget | ✅ Android 可调整尺寸 | ✅ 5+种 | ✅ 3种 | ✅ | ✅ | ✅ |
| iOS Widget | ⚠️ WidgetKit + Xcode Extension target + 锁屏 accessory family 已补，签名/真机待验证 | ✅ | ✅ | ✅ | ✅ | ✅ |
| **成就/游戏化** | | | | | | |
| 成就徽章 | ✅ | ❌ | ✅ Karma | ✅ 非常丰富 | ✅ 种树/贴纸 | ❌ |
| 进度条 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| 排行榜 | ✅ 共享/专注/全局榜 | ❌ | ❌ | ✅ | ✅ | ❌ |
| 虚拟奖励/货币 | ✅ 时光币 | ❌ | ❌ | ✅ 番茄币 | ✅ 金币 | ❌ |
| **数据同步与备份** | | | | | | |
| 云同步 | ✅ 自建后端 | ✅ | ✅ | ✅ | ✅ | ✅ OneDrive |
| 删除防复活 | ✅ 删除墓碑 + 新旧时间过滤 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 账号资料 | ✅ 用户名/邮箱登录 + 验证码 + 找回密码 + 头像/资料修改 + 登出资料清理 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 管理后台 | ✅ 用户/公告/反馈/邀请码/日志分页 + 邀请码搜索 + 反馈筛选导出 + 批量处理/删除确认 | ❌ | ❌ | ❌ | ❌ | ❌ |
| 本地备份/导出 | ✅ JSON + CSV/Markdown | ✅ | ✅ CSV | ✅ | ❌ | ❌ |
| ICS 日历导出 | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| WebDAV 云盘备份 | ✅ OpenList/坚果云/NAS | ❌ | ❌ | ❌ | ❌ | ❌ |
| **智能化 / AI** | | | | | | |
| AI 任务分解 | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| AI 周报 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 智能日程建议 | ✅ 今日建议 | ✅ | ✅ | ❌ | ❌ | ✅ My Day |
| 自然语言解析 | ✅ 中英文日期解析 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 日记智能总结/情绪洞察 | ✅ 本地规则引擎 | ❌ | ❌ | ❌ | ❌ | ❌ |
| **特色功能** | | | | | | |
| 课程表 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| 倒数日 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 纪念日 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 老黄历/黄道吉日 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 应用锁 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| 全局搜索 | ✅ 10类数据含日程 | ✅ | ✅ | ❌ | ❌ | ✅ |
| 主题换肤 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **平台支持** | | | | | | |
| Android | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| iOS | ✅ Flutter | ✅ | ✅ | ✅ | ✅ | ✅ |
| macOS/Windows | ✅ Flutter | ✅ | ✅ | ❌ | ❌ | ✅ |
| Web | ✅ Flutter Web | ✅ | ✅ | ❌ | ❌ | ✅ |
| **商业模式** | | | | | | |
| 定价 | 免费自部署 | 订阅 ¥139/年 | 订阅 $48/年 | 免费+广告/订阅 | 买断 ¥12 | 免费(含M365) |

---

## 2. 多仪现有能力评估

### 2.1 核心优势

多仪是一款**功能高度集成**的个人效率工具，在单一应用内聚合了竞品需要 2-3 个独立 app 才能覆盖的场景：

| 能力域 | 实现深度 | 评价 |
|---|---|---|
| 待办管理 | 四象限 + 5级优先级 + 子任务 + 重复规则 + 自动顺延 + 标签分组 + Markdown 描述 | **较完整**，核心数据模型健全 |
| 习惯追踪 | 正/负向 + 计量单位 + 热力图 + 连续天数 + 弹性周/月目标 + 分类标签 | **业内少有**的正负向双模型和热力图 |
| 目标管理 | 6 分类 + 固定/随机调度 + 推荐目标库 + 节假日跳过 | **独占优势**，竞品均无独立目标模块 |
| 专注模式 | 番茄钟(25/5/15 可配) + 31 条白噪音单音轨 + FocusLink 任务关联 | 基本完整，与任务联动是亮点 |
| 日历 | 月/周/日/三日/年视图 + 日视图时间线 + 本地全天/多日日程 + 农历/节气 + 多数据源聚合 | 视图体系更接近滴答清单，仍需补第三方订阅账号真机验证和真机回归 |
| 日记 | 心情记录 + 心情热力图 + 连续天数统计 | 差异化功能，竞品普遍缺失 |
| 笔记 | 轻量便签 | 最小可用 |
| 课程表 | 周课程格 | 对学生群体有用 |
| 倒数日/纪念日 | 独立模块 + 提醒 | 竞品多需独立 app |
| 老黄历 | 农历转换 + 节气 + 宜忌 | 中国用户文化刚需 |
| 提醒系统 | 双通道(push/alarm) + ReminderPlan 多次提醒 | 架构先进，分离通知和闹钟 |
| 成就系统 | 多维度徽章 + 进度条 + AchievementEngine + 时光币奖励 + 成长等级 + 每日/每周挑战 + 主题/专注背景/头像框/卡片皮肤兑换 | 有体系，仍可继续补更多装饰和社交激励 |
| 统计 | 任务/专注/习惯/日记 + 时间审计 + 周/月/年 + 交叉分析 + 四象限执行分布 | 基本完备，已补专注/待办、习惯/待办、日记/专注相关性、时间分类占比趋势、时间投入 × 待办产出效率和当前待办池四象限执行分布 |
| 数据同步 | 自建后端 + 云同步 + JSON 备份 + ICS 导出 | 数据主权在用户手中 |
| 共享协作 | Workspace 模型 + 邀请码 + 角色权限(owner/editor/viewer) | **已有框架**，但功能深度不足 |
| AI | 任务分解 + 周报复盘 + 服务端代理 | 已落地但场景有限 |
| 快捷捕获 | 自然语言待办 + Android 通知栏快捷添加 + 系统分享文本 + 可保存待办/习惯快捷模板 | 记录入口接近滴答清单/Todoist 高频路径，通知 action 文本会直接转成智能待办 |
| 跨平台 | Flutter（Android/iOS/macOS/Windows/Web） | 一套代码全平台覆盖 |

### 2.2 技术栈评估

- **框架**: Flutter + Provider 状态管理
- **本地持久化**: SharedPreferences（轻量但面临大数据量瓶颈）
- **后端**: 自建 API（Go/Node 推测），支持认证、同步、AI 代理
- **通知**: 双通道架构 (duoyi_general / duoyi_alarm)，ReminderScheduler 统一调度
- **音频**: audioplayers 包，ReleaseMode.loop 无缝循环
- **图表**: fl_chart
- **小组件**: home_widget 包，Android 已暴露 10 个可见独立小组件；iOS 已补 10 个 WidgetKit kind、App Group 数据契约、Xcode Extension target 和锁屏 accessoryInline/Circular/Rectangular family，签名/真机待验证

---

## 3. 核心差距分析（按功能维度）

### 3.1 任务管理

#### 已有
- 四象限分类（`EisenhowerQuadrant` 四值枚举）
- 5 级优先级（none/low/medium/high/urgent）
- 子任务 (`Subtask` 模型) 含自动驱动父任务完成态
- 重复规则 (`RecurrenceRule`)
- 标签、分组 (`listGroupId/listGroupName`)
- 自动顺延 (`PostponeRecord` + `DailyRollover`)
- 快速添加 (`QuickCaptureFab`)
- 排序 (sortOrder + 优先级倒序 + 创建时间)
- 工作区隔离 (`workspaceId`)
- 完成归档策略 (`CompletionVisibilityPolicy`)
- 看板视图 (`_TodoKanbanView` + `test/screens/todo_kanban_view_test.dart`)
- 自定义筛选视图 (`lib/core/todo_filters.dart` + `_TodoFilterBar`)，支持象限、优先级、日期状态、完成状态、标签和清单组合筛选
- 批量操作 (`TodoProvider.completeTodos/reopenTodos/deleteTodos/updateTodosQuadrant/updateTodosPriority` + `_TodoBatchActionBar`)，支持当前筛选视图内多选、全选/反选、完成、恢复、移动象限、改优先级和删除
- 清单内拖拽排序 (`ReorderableListView.builder` + `TodoProvider.reorderVisibleTodos`)，使用显式拖拽把手，兼容自定义筛选和批量选择长按
- 任务描述 Markdown 编辑/预览 (`TodoDetailScreen` + `NoteBlock.fromMarkdown`)，支持标题、加粗、斜体、引用、列表、清单、代码和链接工具栏，并继续存入既有 `notes` 字段兼容旧数据
- 自然语言日期解析 (`SmartDateParser` + `SmartTodoDraftBuilder`)，创建任务时可识别中英文日期/时间并生成截止日与提醒，已覆盖中文相对日期、绝对月日/显式年份、中文数字时间和“今晚八点/明早9点”等高频口语，也覆盖 `tomorrow at 3pm`、`next Monday 9:30am`、`in 3 days at 2pm`、`May 20 at 3pm`、`tonight 8` 等英文基础短语；待办手动重复规则编辑器支持频率、间隔、每周日期、每月日期、结束日期和重复次数；智能待办草稿还会把「每天」「每天的站会」「每两天」「每周二四的英语课」「每周末上午10点」「每2周一」「每周一三五」「每月15日」「每两个月15日」「每天上午9点背单词直到5月20日」「每周一上午9点写周报共10次」、`every Monday`、`every weekday`、`every weekend`、`every other day`、`every 2 weeks Monday`、`every Monday until May 20`、`every other day for 6 times` 等基础重复、间隔重复、周末重复、截止日期和重复次数短语写入 `TodoItem.recurrence`，并按 `maxOccurrences` 停止生成

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| 暂无已确认代码级缺口 | — | 自定义筛选、批量操作、拖拽排序和 Markdown 描述已覆盖；后续以真机交互、重复任务和权限回归为主 | — |

### 3.2 日历与日程

#### 已有
- 多视图：`CalendarMonthGrid`（月）、`CalendarWeekStrip`（周）、`CalendarDayAgenda`（日）、`_CalendarThreeDayView`（三日）和 `_CalendarYearOverview`（年）
- 三日视图：`_CalendarThreeDayView` 复用日程聚合、类型筛选、项目筛选和日视图详情能力，桌面并列展示三天，窄屏横向滚动
- 日视图时间线：`CalendarDayAgenda` 将有时间事件渲染到 `_CalendarDayTimeGrid` 24 小时刻度中，按分钟定位、裁剪跨日边界并用紧凑卡片展示短事件；全天/无时间事件独立分区
- 全天/多日事件显示索引：`CalendarProvider.getEventsForDate/dateEventTypes/filteredDateEventTypes` 已按 `CalendarEvent.endDate` 展开日期范围，支持跨日事件在每个覆盖日期显示，并按 ICS 全天 `DTEND` 午夜排他语义处理
- 本地创建/编辑全天或多日日程：`CalendarEventType.event` + `CalendarProvider.addLocalEvent/updateLocalEvent/deleteLocalEvent` 持久化用户创建的日程，日历 FAB 入口复用 `showLocalCalendarEventEditor`，可设置全天、开始/结束日期、开始/结束时间、颜色和备注，并进入同一日/周/月/三日/年索引
- 日历详情回写：`CalendarEventSheet` 可直接完成/改期/调整待办时间，改期目标、纪念日、倒数日和时间足迹，调整时间足迹开始/时长，删除课程/日记/习惯等源事件，并复用纪念日/倒数日/课程/日记/习惯原编辑器直接回写原模块 Provider
- 数据聚合：`CalendarAggregator` 整合 Todo/Habit/Pomodoro/Anniversary/Course/Diary/Countdown/Goal
- 农历 + 节气 + 节日 (`LunarCalendar`)
- 快速添加任务到指定日期
- ICS 导出 (`IcsExporter`)

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **第三方日历账号真机验证** | 滴答清单、Todoist、Microsoft To Do | 已补 ICS 订阅、Google/Outlook OAuth 只读拉取、通用 CalDAV 写回，以及 iCloud/Apple Calendar CalDAV 快速配置入口；仍需生产账号和真机验证 | **P1** |

### 3.3 提醒系统

#### 已有
- 双通道架构：`duoyi_general`（通知推送） + `duoyi_alarm`（闹钟级全屏高优先级）
- `ReminderConfig`（kind: push/alarm + hour/minute）
- `ReminderPlan`（多次提醒计划）
- 提前提醒偏移模板：5 / 15 / 30 / 60 分钟，1 / 2 / 3 天
- 位置提醒 (`LocationReminderProvider` / `LocationReminderEngine` / `LocationReminderController` / `LocationGeofenceService`)，支持进入/离开半径、one-shot、手动位置测试、通知历史、任务详情关联创建、前台/后台位置授权引导和 Android 系统 geofence 后台调度
- `ReminderScheduler` 统一调度器
- 通知健康检查 (`PermissionHealthService`)

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **后台地理围栏真机验证** | 滴答清单"到达公司时提醒"、Todoist 地理围栏 | Android 已接入系统 GeofencingClient 调度、后台接收器、深链通知和前台/后台位置授权引导；仍需真机验证 OEM 省电策略 | **P3** |
| **邮件提醒** | Todoist 的邮件提醒通道 | 已补 `ReminderKind.email`、提醒编辑器“邮件”选项、客户端 `BackendReminderEmailSink`、后端 `/api/reminders/email/*` 调度接口、`reminder_email_jobs` 表、SMTP 配置项、到期派发循环、管理员后台“邮件提醒投递”SMTP 配置表单和“测试提醒邮件”诊断按钮；未登录或未配置 SMTP 时不误走本地通知/闹钟 | ✅ |

### 3.4 专注模式

#### 已有
- 番茄钟：可配时长（默认 25/5/15 分钟）+ 4 轮长休息
- 白噪音：31 条单音轨（rain, forest, cafe, waves, brown_noise, night_rain, fan, pink_noise, deep_stream, thunderstorm, storm_rain, campfire, dawn_birds, waterfall, brook, river, crickets, white_stream, clock, keyboard, wind, train_station, classroom, pebble_beach, mall, restaurant, garden_birds, country_night, shallow_river, veranda_rain, breeze_birds）
- `FocusSoundService`：单例播放、loop 循环、fadeIn/fadeOut
- `FocusLink`：任务与专注预设绑定
- 自动开始休息/专注可配
- 休息阶段白噪音可配
- Android 专注勿扰联动：`FocusDndService` + `duoyi/focus_dnd` MethodChannel，在专注开始时可开启系统 DND，暂停/结束/重置后恢复原状态；未授权时提示去系统设置，不阻塞计时
- 严格专注 (`PomodoroConfig.strictFocusMode` + `PomodoroFocusPenalty`): 专注页可开启严格专注，专注中暂停、跳过、重置或离开应用会弹确认并写入 `pomodoro_focus_penalties` ledger，记录原因、影响时长、任务、标签和自习室归属，纳入备份和云同步
- Android 分心应用监控/拦截：`FocusDistractionService` + `duoyi/focus_distraction` MethodChannel 接入 UsageStats 使用情况权限和 Accessibility 辅助功能服务；严格专注中可配置分心应用包名，检测到前台切到指定 App 时写入“打开分心应用”惩罚记录，辅助功能授权后会拉回多仪专注页
- 自定义白噪音导入 (`CustomFocusSoundProvider` + `FocusSoundService`): 支持从系统文件选择器导入 MP3/M4A/WAV/AAC/OGG 到应用沙盒，专注页和目标专注联动选择列表都会展示自定义音轨，并通过 `DeviceFileSource` 播放
- 专注历史记录 (`PomodoroSession`): 历史卡片和日历详情都支持编辑会话，变更会同步回 `PomodoroProvider` 和时间足迹
- 习惯时间足迹联动：分钟/小时单位的正向习惯会按本次打卡数量自动写入 `TimeEntrySource.habit`，撤销打卡同步删除对应自动记录；非时间单位习惯继续支持手动补记
- 今日专注统计（时长 + 次数）
- 专注标签统计 (`FocusTagStats` + `StatisticsScreen`): 统计页按当前周期汇总标签专注分钟、次数、平均时长和占比，未标记会话自动归入“未标记”；Top 标签按本周/本月每日或本年每月展示折线趋势
- 专注自习室 (`FocusRoomProvider` + `PomodoroSession.focusRoomId` + `FocusRoomApi`): 专注页可加入/创建自习室，选择本轮计入房间，并支持邀请码管理、有效期、使用次数限制、复制、输入邀请码加入和撤销；完成会话会带房间归属，本地按周生成成员排行榜和目标进度，数据纳入备份和云同步；后端已补 `focus_room_presence`、`focus_room_invites`、`focus_friends`、`focus_friend_request_log`、房间心跳、离开、服务端周榜、房间 WebSocket/SSE 排行事件流、全局榜 WebSocket/SSE 排行事件流、创建邀请、列出邀请、撤销邀请、接受邀请、发送/同意/拒绝/取消专注好友申请、24 小时申请限流、移除好友、好友列表和好友榜接口，并对短时间重复 heartbeat、异常 session_count 跳变、超限周专注时长/次数写入 `risk_flags`/`risk_summary`，房间榜、好友榜和全局榜都会暴露服务端风控证据；专注页可优先展示服务端排行、实时房间状态、在线人数、服务端好友榜与实时全局榜，未登录、接口失败或实时通道不可用时回退本地榜/轮询
- 好友/全局专注排行榜 (`buildFocusSocialRanking` + `_FocusSocialRankingCard`): 专注页展示好友榜和全局榜，按本周有效专注时长排名；好友榜已支持按用户名发送好友申请、收到申请同意/拒绝、发出申请取消、移除服务端好友、展示在线状态并优先使用服务端好友榜；基础反作弊会对单次超过 4 小时、单日超过 12 小时、未来记录做封顶/忽略和可疑标记

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **白噪音听感验收** | 自然声、低频噪声应和文案一致 | 用户对“呼呼噪音”反馈明确，需真机听感复核 | **P1** |
| **系统级屏蔽指定 App** | 番茄TODO "学霸模式"、Forest 核心功能 | 已补 Android 系统 DND 勿扰联动、严格专注中断惩罚 ledger、UsageStats 分心应用前台监控和 Accessibility 辅助功能拉回拦截；VPN/设备管理级封锁、不同 ROM 保活和 iOS 同类能力仍需继续验证 | **P2** |
| **实时/后端社交自习室** | 番茄TODO 自习室、Forest 多人种树 | 已补本地自习室、房间周榜、好友榜、全局榜、会话归属、后端心跳/服务端周榜、房间 WebSocket 双向事件、房间 SSE 回退、全局榜 WebSocket/SSE 实时事件、服务端好友关系/在线状态/好友榜、好友申请审批/拒绝/取消/限流和邀请码管理/有效期/次数限制/接受/撤销，并已落地 `risk_flags`/`risk_summary`、重复 heartbeat 节流、`session_count` 跳变封顶、超限周时长/次数标记等基础服务端风控；仍缺多端真机 E2E、生产级持续风控和线上验证 | **P2** |
| **正计时模式** | 滴答清单持续时间 | 已补自由计时入口和会话记录，覆盖非番茄节奏专注 | ✅ |
| **自定义音频导入** | 番茄TODO 本地音乐/白噪音扩展 | 已补本地导入、沙盒持久化和播放，仍需真机验证不同格式兼容性 | ✅ |
| **专注标签统计** | Forest/番茄TODO 按类别复盘专注投入 | 已补当前周期标签排行、占比和 Top 标签趋势折线 | ✅ |
| **专注报告导出** | 番茄TODO 详细报告 | 已补专注专项 Markdown 模板：本周/本月报告汇总专注总时长、次数、平均/最长单次、活跃天数、严格专注中断和标签投入，可从番茄钟历史页一键复制 | ✅ |

### 3.5 习惯追踪

#### 已有
- 正/负向双模型 (`HabitKind.positive / .negative`)
- 计量单位 (`unit`: 次/杯/分钟)
- 热力图 (`HabitHeatmap`)
- 连续天数 / 最佳连续 (`currentStreak / bestStreak`)
- 活跃星期 (`activeWeekdays`)
- 弹性周/月目标 (`flexTarget + flexPeriod`，旧 `weeklyTarget` 保持兼容)
- 分类分组 + 标签（创建/编辑可设置分组，热力图页按 `Habit.category` 折叠展示）
- 开始/结束日期
- 提醒 (`remind + remindHour/remindMinute`)
- 模板库 (`HabitTemplates.byCategory`，已扩展为 6 类 30 个模板，覆盖身体健康/学习提升/心理调节/生活习惯/社交沟通/职业发展；模板含中英文名称、单位和每日/每周/每月推荐频率)
- 弹性打卡规则（创建/编辑可切换每周/每月至少 N 次，连续统计按周/月周期判定，详情页展示「本周/本月 x/y」）
- 长期趋势 drill-down（习惯详情支持 14/30/90/365 天切换、达标率、较上期、最长连续和区间明细）
- 打卡反馈（达标徽章、卡片轻量动效、触感反馈、系统点击音和浮动提示）

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| 暂无已确认代码级缺口 | — | 习惯分组、模板、反馈和长期趋势已覆盖；后续以真机交互和数据准确性回归为主 | — |

> 注：多仪的习惯模块**总体领先**大部分竞品（正/负向 + 热力图 + 计量单位的组合在竞品中罕见），差距较小。

### 3.6 统计分析

#### 已有
- 周/月/年三维度切换 (`_Range.week / .month / .year`)
- 任务完成数、专注时长/次数、日记条数、习惯完成天数
- fl_chart 图表
- 时间审计 (`TimeAuditScreen` + `TimeAuditProvider`)
- 时间分类聚合 (`secondsByCategory`)
- 生产力评分展示 (`PeriodReport.productivityScore` + `TodayScreen` 本周效率摘要 + `StatisticsScreen` 效率对比卡片 + `UserProfile.productivityScore`)
- 周期对比展示 (`ReportEngine.compare` / `ReportComparison`，统计页覆盖效率分、完成率、习惯、专注、时间足迹差值/百分比/趋势方向)
- 多周期效率趋势折线 (`StatisticsScreen` 近 6 周 / 近 6 个月 / 近 5 年同段效率分)
- 趋势洞察、历史摘要与逐周期 drill-down (`StatisticsScreen` 自动解读、历史最佳、平均分、当前排名、每个周期的效率分/待办/专注/习惯/时间足迹明细)
- 周报/月报/年度报告成品层 (`PeriodReportDigest` + `StatisticsScreen` 报告卡): 基于周期报告和环比数据生成摘要、关键洞察、Markdown 文案和分享图入口
- GitHub 风格活动热力图 (`StatisticsScreen` 年度活动热力图，聚合待办、习惯、专注、时间足迹、日记)
- 多维交叉分析 (`ReportCrossAnalysis` + `StatisticsScreen`): 展示专注分钟数与待办完成数、习惯达标次数与待办完成数、日记篇数与专注分钟数相关性散点图，时间分类占比趋势堆叠图，以及时间投入 × 待办产出效率（`timeOutputEfficiency`，按时间桶统计每小时完成待办数）
- 四象限执行分布 (`StatisticsScreen`): 按当前待办池展示重要紧急/重要不紧急/紧急不重要/不重要不紧急四类总数、未完成、逾期、今日到期、已完成、占比和行动建议
- 统计报告 Markdown/PNG/PDF 导出 (`StatisticsScreen` + `pdf`，`statistics_report_export_static_test`): PDF 支持视觉版、归档版、简报版、仪表版和时间线版五种模板，并通过随包 CJK 字体输出可检索中文文字层
- 每日复盘/周报/月报/年报定时通知 (`NotificationSettingsScreen` 报告推送 + `main.dart` `_syncReportDigestReminders` + `ReportReminderConfig`): 可分别开启每日复盘、周报、月报和年报，每日复盘支持自定义推送时间，周报支持自定义星期几和推送时间，月报支持自定义每月日期和推送时间，年报支持自定义月份、日期和推送时间，选择 29-31 日时会按短月份自动夹到月末；通知正文由 `PeriodReportDigest.notificationBody` 动态汇总效率分、完成项、专注、习惯、时间足迹和环比变化，并在待办/习惯/专注/时间足迹变化后 debounce 重排，点击 `duoyi://report/...` 直达统计报表
- 云端个性化报告解读 (`StatisticsScreen` + `AiService.personalizedReportReview`): 当前周期报告卡可一键调用服务端 `/api/ai/chat`，基于周/月/年报告 Markdown 生成结构化个性化解读、未来 7 天行动建议，并写入 AI 历史

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **趋势详情 drill-down** | Todoist Karma、番茄TODO 学习力 | 已在趋势卡内补逐周期详情，并新增“查看趋势详情”独立页：展示趋势概览、趋势洞察、历史最佳、平均分、当前排名，以及每个趋势点的日期范围、效率分、较上期变化、待办、专注、习惯和时间足迹 | ✅ |
| **PDF/模板化报告导出** | 滴答清单 PDF、番茄TODO 模板图 | 当前周期报告卡已支持 Markdown、PNG 分享图、A4 PDF 视觉版/归档版/简报版/仪表版/时间线版五种模板导出，并通过随包 CJK 字体生成可检索中文文字层；保存后会拉起系统分享面板 | ✅ |
| **摘要推送深化** | Todoist "生产力周报" | 已有每日任务摘要、每日复盘、周报/月报/年报定时通知、动态摘要正文、自定义日/周/月/年推送时间和点击直达统计页；统计页报告卡已补云端 AI 个性化解读和 AI 历史保存 | ✅ |

### 3.7 共享协作

#### 已有
- `Workspace` 模型：id, name, ownerUserId, members
- `WorkspaceRole`：owner / editor / viewer 三级权限
- `ShareProvider`：创建空间、邀请、加入、退出
- `ShareScreen`：邀请码/二维码分享
- `TodoItem.workspaceId` 支持按空间隔离
- `GoalItem.workspaceId` 支持共享目标归属，目标编辑页通过 `ShareProvider.canEdit` 限制 viewer 写入，目标列表显示共享空间标识
- `CalendarEvent.workspaceId` 支持本地共享日程，日历新增/编辑会带入当前空间，日程数据随 workspace payload 的 `calendar_events` 往返同步
- @ 提及通知：共享空间评论和任务评论会解析 `@用户名` / `@userId`，服务端写入未读提及收件箱，分享页展示未读角标并可标记已读
- 共享日历：共享待办、共享目标和本地共享日程都会进入日历聚合，日历页可按共享空间筛选月/周/日/三日/年视图，项目筛选和项目详情会跟随当前空间收窄

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **多人端到端回归** | 滴答清单、Todoist 成熟协作 | 任务负责人、任务级评论、空间评论、动态流、成员头像/角色徽标和成员排行榜已落地；仍需多账号真机/后端联调确认权限、刷新和冲突体验 | **P2** |
| **@提及通知** | Todoist | 已补服务端 mention inbox、未读角标和标记已读；后续可接入系统推送/邮件提醒 | ✅ |
| **共享日历/目标** | 滴答清单共享日历、Todoist 共享项目 | 已补共享空间维度筛选：共享待办、共享目标和本地共享日程进入日历后可按空间查看，且月/周/日/三日/年视图、项目筛选和项目详情共用同一空间过滤；仍需多人真机数据回归 | ✅ |

### 3.8 小组件 (Widget)

#### 已有
- 10 个可见独立 Android 小组件：今日待办、专注、习惯、月历、今日日程、目标、课程表、随手记、纪念日、日记
- 不再暴露“概览/组合”入口；历史 `DuoyiWidgetProvider` 仅作为兼容类和资源保留，不在 Manifest 注册，也不会作为可见入口被创建
- 今日待办支持 Top3 列表、勾选完成和“+ 添加”快捷入口
- 习惯小组件接收 `HomeWidgetService` 推送的今日可打卡正向习惯，提示行可直接深链 `duoyi://action/checkin_habit?id=...` 完成打卡
- 专注小组件接收 `focus_timer_running`、剩余秒数、总秒数和预计结束时间；Android 显示倒计时快照/预计结束时间，iOS WidgetKit 使用 `.timer` 文本展示倒计时
- Android 系统分享面板可接收 `text/plain`，进入应用后选择创建智能待办或保存为笔记
- 数据通过 `HomeWidgetService` 推送；iOS 静态契约测试会校验 10 个 WidgetKit kind、App Group、deep link、accessory family、Xcode Extension target 和共享数据 key（含底部导航 `nav_*` 文案），但不替代签名或真机添加验证

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **iOS Widget** | 所有主流竞品均支持 | 已补 10 个独立 WidgetKit kind、App Group entitlement、Runner URL scheme、Flutter 刷新契约、Xcode Extension target、待办详情/完成、快捷添加、习惯打卡、开始专注、底部导航共享文案 Link，以及锁屏 accessoryInline/Circular/Rectangular 小尺寸布局；静态测试已锁定资源/契约完整性，仍缺开发者账号签名和真机添加验证 | **P1** |
| **跨端 Widget parity** | 滴答清单、Todoist、指尖时光 iOS/Pad Widget | Android 已有待办快捷添加/习惯打卡；iOS 已补共享数据展示、deep-link 交互骨架和锁屏 accessory family，真机 parity 待验证 | **P1** |
| **更多尺寸（1x1, 2x2, 4x2 等）** | 滴答清单 5+ 种布局 | Android 已声明可调整尺寸；iOS 已覆盖 systemSmall/Medium/Large/ExtraLarge 与 accessoryInline/Circular/Rectangular，仍需真机尺寸/刷新验证 | **P2** |
| **专注计时 Widget** | 番茄TODO | 已补 Android/iOS 共享倒计时数据契约、Android 倒计时快照和 iOS WidgetKit `.timer` 展示；逐秒刷新受系统小组件刷新策略限制，仍需真机 launcher 验证 | **P3** |
| **iOS/跨端习惯打卡 Widget** | 滴答清单 | Android 已有基础打卡入口；iOS 已能读取 `habit_quick_check_id` 并生成 `duoyi://action/checkin_habit?id=...` Link，真机签名后需验证点击链路 | **P3** |

### 3.9 成就/游戏化

#### 已有
- `Achievement` 模型：id/title/description/icon/color/unlocked/current/target
- `AchievementEngine`：evaluate 批量判定 + 进度计算
- 多维度覆盖（待办/习惯/专注/日记/目标/纪念日/课程/笔记/主题）
- `AchievementContext` 聚合快照
- 进度条可视化
- 时光币虚拟奖励 (`VirtualRewardRules` + `AchievementProvider`): 完成待办、习惯打卡、完成专注、写日记、目标/里程碑和成就解锁会入账；成就页展示余额与最近奖励/兑换；`duoyi_virtual_rewards` 已进入备份和云同步 payload
- 成长等级 (`GrowthLevels`): 基于累计时光币派生 Lv.1-Lv.15 等级、称号、距下级所需时光币和进度条，成就页与成就分享图都会展示长期成长身份
- 奖励商店基础闭环 (`ThemeProvider` + `ThemePickerScreen`): 默认主题、经典专注背景、简洁头像框和素净卡片免费，高级主题、专注背景、头像框、卡片皮肤需要时光币解锁，兑换后写入 `theme_shop_state` 并进入备份和云同步；番茄钟页会应用已启用的专注背景，我的页会应用已启用的头像框，默认 `AppSurfaceCard` 会应用已启用的卡片皮肤

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **更多装饰/权益兑换** | 番茄TODO "番茄币"换装饰、Forest "金币"种真树 | 已有主题、专注背景、头像框和卡片皮肤兑换；后续可继续补更多细分装饰 | ✅ |
| **好友/全局排行榜** | 番茄TODO 自习室排名、Forest 好友排行 | 已有共享空间成员榜、专注自习室本地/服务端周榜、服务端好友关系、好友申请审批/拒绝/取消/限流、好友在线状态、好友专注榜、全局专注榜、全局榜 WebSocket/SSE 实时事件、基础反作弊封顶，以及服务端 `risk_flags`/`risk_summary` 风控证据；仍缺生产级持续风控和线上验证 | **P3** |
| **成就分享** | 番茄TODO 生成海报 | 已补成就页分享图：展示解锁进度、时光币、最近解锁徽章，支持复制文案、保存 PNG 并拉起系统分享面板 | **P3** |
| **每日/每周挑战** | 番茄TODO 每日任务 | 已补成就页每日/每周挑战：按今日完成待办、习惯打卡、专注分钟、日记复盘，以及本周待办、习惯、专注、日记和活跃天数生成短期目标；完成后按日/周周期发放一次性时光币奖励 | ✅ |
| **等级系统** | 番茄TODO 学霸等级 | 已补基于累计时光币的 Lv.1-Lv.15 成长等级、称号、距下级进度和成就分享图展示 | ✅ |

### 3.10 数据同步与备份

#### 已有
- 自建后端云同步（`CloudSyncProvider` + `ApiClient`）
- 本地变更通过约 300 毫秒短窗口合并上传；服务端事务提交后向同账号在线连接发布 `/api/sync/events` SSE 修订通知，客户端按集合 hash 调用 `/api/sync/pull` 并回载 Provider，不定时查询 `/api/sync/status`。pending/inflight 期间保留通知，重复修订去重，断线重连首帧及恢复前台补齐变化。本地修改仍优先调用 `/api/sync/item-delta`，缺少条目基线时回退 `/api/sync/delta`，保留显式删除墓碑与三方合并。
- 删除墓碑同步：客户端和服务端都合并 `deleted_items`，客户端落盘云端列表前按墓碑过滤旧 `habits`、`pomodoro_sessions`、`time_entries` 等记录，避免已删除习惯打卡、专注记录和时间足迹被旧云端数据复活
- 脏数据标记（`hasPendingChanges` + badge）
- 冷启动抑制误报 (`suppressDirtyMarkWhile`)
- JSON 全量导出 (`BackupService.exportAll`)
- WebDAV 云盘备份 (`WebDavBackupService` + `BackupScreen`): 可配置 OpenList、坚果云、NAS 等兼容 WebDAV 的云盘，保存 URL/账号/目录/文件名后，一键上传当前全量 JSON，也可从云端同一路径合并或覆盖恢复；备份恢复和竞品 CSV/JSON 迁移均支持从本地文件选择器读取，不再只能粘贴文本；竞品迁移已补来源选择、解析预览、去重确认和导入结果弹窗，结果弹窗可撤销本次导入并恢复导入前本地快照
- 单模块 CSV/Markdown 导出 (`ModuleExporter` + `BackupScreen`)，覆盖待办、习惯、时间足迹、笔记、日记、纪念日和目标
- ICS 日历导出 (`IcsExporter`)
- 特性开关保护 (`FeatureFlags.cloudSyncV2`)

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **增量同步 / 冲突合并** | 滴答清单、Todoist 的实时同步 | 已补 `updatedAt` 合并、字段差异与冲突记录、删除墓碑、提交后 SSE 修订通知、集合 hash 增量拉取及集合/条目增量上传；待上传或同步中的远端修订继续排队，空闲不探测数据版本。仍需多设备实机端到端验证。 | **P1** |
| **多设备实时同步** | 所有主流竞品 | 已补本地修改短窗口上传、同账号在线连接主动通知、断线补齐及账号/服务器/凭证隔离；当前进程内分发限单 worker，多 worker/多实例需共享事件总线，系统挂起后在恢复前台补齐。仍需双端实机及生产长连接验证。 | **P2** |
| **备份到云盘（Google Drive / iCloud）** | 番茄TODO | 已补 WebDAV 云盘备份，覆盖 OpenList、坚果云、NAS 等通用私有云路径；Google Drive / iCloud 原生授权仍可继续扩展 | ✅ |
| **导入其他 App 数据** | 滴答清单"从 Todoist 迁移" | 已补待办/习惯/笔记/日程/纪念日/生日/倒数日/时间足迹迁移：备份页支持粘贴或选择本地 Todoist / 滴答清单 / 指尖时光风格 CSV / JSON 文件；导入前可选择来源、查看模块数量/样例/解析提示，并需确认“重复项跳过、不覆盖本机数据”策略；导入后展示各模块写入数量、解析跳过和重复跳过数量，并可一键撤销本次导入、恢复导入前本地快照。解析覆盖任务标题、完成状态、完成时间、优先级、四象限、清单、截止日、开始/结束时间、重复、提醒、标签和备注；可按 `type=habit/note/event/birthday/anniversary/countdown/time_entry` 迁入习惯目标、重复日、打卡记录、提醒时间、笔记正文、附件链接、本地日历日程的开始/结束时间、日历/项目和备注、生日/纪念日/倒数日日期、历法、分类、置顶与提醒，以及时间足迹标题、开始/结束时间、时长、分类、来源和备注；账号级 JSON 包络已支持 `projects/lists/taskLists/tags/categories/workspaces/collections/folders` 及数组或 ID 映射形式的嵌套任务继承；导入前可打开高级字段映射，将任意来源字段映射到标题、日期、截止日、清单、标签、优先级、四象限、完成状态、提醒、重复、备注、模块类型、目标、单位、分类和时长等字段。后续剩余是真机文件选择回归 | **P4** |

### 3.11 智能化 / AI

#### 已有
- AI 任务分解 (`breakDownTask`): 将目标拆解为 3-7 条可执行子任务
- AI 周报 (`weeklyReview`): 基于本周数据生成 80-150 字复盘建议
- 服务端代理 (`/api/ai/chat`): 用户无需配置 key，管理员统一管理
- AI 历史记录 (`AiReviewEntry` + `AiHistoryScreen`)
- 自然语言待办创建已通过 `SmartDateParser` / `SmartTodoDraftBuilder` 接入快速待办、AI 拆解、系统分享和快捷模板创建路径
- AI 对话式操作 (`AiCommandParser` + `QuickCaptureFab`): 快捷入口支持“添加待办… / 记笔记… / 写日记… / 开始专注”等自然语言指令，先预览解析结果，再本地执行创建待办、保存笔记、写入日记或启动专注
- 智能日程建议 (`SmartScheduleAdvisor` + `TodayScreen`): 根据截止日、优先级、四象限和任务日期每日推荐 5 条任务，并可一键“加入今日”
- 智能习惯洞察 (`HabitInsightEngine` + `HabitScreen`): 基于 30 天趋势自动生成整体达标率、进步、下滑、连续性和需关注习惯提示
- 本地日记智能总结/情绪洞察 (`DiaryInsightEngine` + `DiaryScreen`): 基于近 30 天日记生成主导心情、情绪走势、主题标签、连续记录和低落心情提醒
- LLM 日记深度复盘 (`DiaryDeepReviewBuilder` + `AiService.deepDiaryReview`): 日记页可调用服务端 AI，对近 30 天日记摘录生成 500-900 字结构化复盘，覆盖近期主线、情绪能量、触发因素、保留做法和未来 7 天行动，并进入 AI 历史

#### 缺失 — 与竞品差距

| 缺失功能 | 竞品参照 | 影响评估 | 优先级 |
|---|---|---|---|
| **云端/LLM 深度日记总结** | — | 已补日记页 AI 深度复盘：基于近 30 天日记、心情、天气、标签和地点生成长篇结构化复盘，并保存到 AI 历史 | ✅ |
| **AI 对话式操作** | Todoist AI 助手 | 已补快捷入口 AI 指令：支持自然语言创建待办、保存笔记、写日记和开始专注；复杂多轮对话仍可继续扩展 | ✅ |

---

## 4. 多仪差异化优势

以下是多仪相对于所有对标竞品的**独占或领先优势**，这些是产品护城河，应当持续强化：

### 4.1 全场景一体化（最核心优势）

多仪在**单一 App** 内集成了：待办 + 习惯 + 目标 + 日历 + 番茄钟 + 日记 + 笔记 + 课程表 + 倒数日 + 纪念日 + 万年历农历/宜忌。

- 滴答清单覆盖 ~70%（缺日记/笔记/目标/倒数日/纪念日/农历宜忌）
- Todoist 覆盖 ~40%（纯任务管理 + 日历）
- 番茄TODO 覆盖 ~50%（缺日历/目标/笔记/纪念日/农历宜忌）
- Forest 覆盖 ~15%（仅专注）
- Microsoft To Do 覆盖 ~30%（纯任务 + 日程）

**用户价值**：避免多 App 切换、数据孤岛，所有生活/学习/工作数据集中管理。

### 4.2 独立目标管理系统（独占）

`GoalItem` 模型 + 6 分类 + 固定/随机调度 + 推荐目标库 + 节假日跳过——这是**所有 5 个竞品都没有的功能**。

- 目标不同于任务：任务是"做什么"，目标是"成为什么"
- 调度策略（随机派发 + 最小间隔 + 周/月上限）支持"不定期推动自己"的场景
- 推荐目标库降低了"不知道设什么目标"的冷启动门槛

### 4.3 正/负向习惯双模型（领先）

`HabitKind.positive` (养成) + `HabitKind.negative` (戒除) 在竞品中罕见：
- 滴答清单仅正向
- 番茄TODO 仅正向
- 负向习惯（戒烟/戒糖/减少手机使用）是真实用户需求

### 4.4 习惯热力图（领先）

`HabitHeatmap` 类似 GitHub 贡献图，在效率 App 中独一无二：
- 滴答清单用柱状图
- 番茄TODO 用日历格
- 热力图在长时间维度下更直观

### 4.5 中国文化特色功能集（差异化）

- **农历/节气**：`LunarCalendar.fromSolar()` + `solarTerm()` + 节日检测
- **万年历宜忌**：`AlmanacScreen` 在万年历内展示农历、节气、节日和宜忌查询，不再保留单独“黄历”入口
- **纪念日**：农历循环纪念（竞品多只支持公历）
- **倒数日**：独立模块，非简单的提前提醒

这些功能在国际化竞品（Todoist、Microsoft To Do、Forest）中完全缺失。

### 4.6 双通道提醒架构（技术领先）

`duoyi_general`（普通通知） + `duoyi_alarm`（闹钟级全屏震动），由 `ReminderScheduler` 统一调度——大多数竞品只有单一通知通道，多仪的分离架构更符合 Android 通知规范。

### 4.7 数据主权/自部署模式

自建后端 + 全量 JSON 导出 + ICS 导出——用户完全掌控数据。对隐私敏感用户（特别是中国市场对数据安全的关注）有天然吸引力。

### 4.8 AI 周报（独占）

`weeklyReview()` 基于本周真实数据生成个性化复盘——目前无竞品有此功能（Todoist 的 Karma 是静态算分，不会生成文字建议）。

---

## 5. 优先补齐建议

基于影响面、实现复杂度、竞品差距综合评估，建议分三阶段推进：

### 第一阶段：核心体验补齐（P0-P1，预计 4-6 周）

解决"用户试用 5 分钟内就能感知到的差距"。

| # | 功能 | 理由 | 预估工作量 |
|---|---|---|---|
| 1 | **自然语言日期解析 UI 回归/扩展** | 中英文核心日期解析已落地到 `SmartDateParser`/`SmartTodoDraftBuilder`、任务创建入口、系统分享和快捷模板；已补中文相对日期、绝对月日/显式年份、中文数字时间和“今晚八点/明早9点”等口语表达，也补了 `tomorrow at 3pm`、`next Monday 9:30am`、`in 3 days at 2pm`、`May 20 at 3pm`、`tonight 8` 等英文基础短语；基础重复、间隔重复、周末重复、截止日期和重复次数短语已可写入 `RecurrenceRule.interval/byWeekdays/endDate/maxOccurrences`，下一步继续做完整 UI 回归和更复杂重复表达。 | 1 周 |
| 2 | **iOS Widget** | 已补 10 个 WidgetKit kind 的 Swift 源码骨架、Flutter App Group 数据契约、Runner URL scheme、Xcode Extension target 和锁屏 accessory family；剩余主要是签名 capability 和真机回归。 | 1 周 |
| 3 | **第三方日历订阅** | 用户已有 Google/Outlook 日程——无法整合 = 无法替代现有工具。实现 CalDAV 只读订阅（解析 ICS URL）是最小成本方案。 | 2 周 |
| 4 | **任务指派** | 共享空间已有 Workspace + 角色体系，`TodoItem` 加 `assigneeId` 字段即可打通任务分配。 | 1 周 |

### 第二阶段：竞争力增强（P2，预计 6-8 周）

解决"用户深度使用后感知到的不足"。

| # | 功能 | 理由 | 预估工作量 |
|---|---|---|---|
| 5 | **看板视图** | 已落地：任务页提供四象限看板列、任务卡片元信息和象限移动菜单。 | ✅ |
| 6 | **白噪音单音轨扩充** | 已扩到 31 条单音轨并超过番茄TODO 30+ 数量门槛；用户明确不要组合音轨，后续以逐项真机听感验收为主。 | ✅ |
| 7 | **生产力评分首页化** | 已落地：TodayScreen 展示本周效率摘要，StatisticsScreen 展示效率对比和趋势。 | ✅ |
| 8 | **增量同步** | 已实现 `updatedAt` 合并、字段级冲突记录、删除墓碑、提交后 SSE 修订通知、集合 hash 增量拉取、集合及条目增量上传；空闲不定时探测数据版本。下一步完成双端实机及生产长连接验证，多 worker 部署前接入共享事件总线。 | 2 周 |
| 9 | **更多 Widget 尺寸+类型** | Android 待办快捷添加、习惯打卡、专注倒计时快照和 iOS WidgetKit 独立 kind/accessory 小尺寸已覆盖；继续做真机尺寸/刷新验证。 | 2 周 |
| 10 | **智能日程建议** | 已落地：TodayScreen 通过 `SmartScheduleAdvisor` 按截止日、优先级、四象限和任务日期推荐 5 条任务，并支持一键加入今日。 | ✅ |
| 11 | **筛选器/自定义视图** | 已落地：任务页按标签、优先级、日期状态、完成状态、象限和清单组合筛选，四象限/列表/看板共用筛选结果。 | ✅ |
| 12 | **批量操作** | 已落地：任务页支持进入批量模式，在当前筛选结果内多选/全选/反选，并批量完成、恢复、移动象限、改优先级和删除。 | ✅ |
| 13 | **任务排序拖拽** | 已落地：列表视图清单内支持显式拖拽把手排序，保持当前筛选序列和批量选择长按互不冲突。 | ✅ |
| 14 | **任务描述 Markdown** | 已落地：任务详情页用工具栏编辑 Markdown 描述，并复用 `NoteBlock` 做预览，兼容既有 `notes` 数据。 | ✅ |
| 15 | **统计趋势详情** | 环比卡片、连续趋势折线、自动解读、历史摘要、逐周期 drill-down 和“查看趋势详情”独立页已落地。 | ✅ |
| 16 | **日记智能总结/情绪洞察** | 已落地：日记页基于 `DiaryInsightEngine` 展示近 30 天主导心情、情绪走势、主题标签、连续记录和低落提醒，并已补 LLM 深度复盘长文生成与 AI 历史保存；后续重点是真机/账号/E2E 回归和更丰富维度。 | ✅ |

### 第三阶段：生态与增长（P3-P4，按需推进）

解决"用户留存和传播"。

| # | 功能 | 理由 | 预估工作量 |
|---|---|---|---|
| 16 | 社交专注/自习室 | 已落地本地自习室、房间选择、每周排行、服务端好友关系/在线状态/好友榜、好友申请审批/拒绝/取消/限流、全局专注榜、全局榜 WebSocket/SSE 实时事件、专注会话归属、后端心跳/服务端房间周榜、WebSocket 双向房间事件、SSE 排行事件流回退、邀请码管理/有效期/次数限制/接受/撤销，以及 `risk_flags`/`risk_summary`、重复 heartbeat 节流、`session_count` 跳变封顶、超限周时长/次数标记等基础服务端风控；下一步补多端真机 E2E、生产级持续风控和线上验证。 | 2-4 周 |
| 17 | 虚拟货币/奖励商店 | 已落地时光币入账、最近奖励/兑换、主题/专注背景/头像框/卡片皮肤解锁、备份和云同步；后端同步列已覆盖 `virtual_rewards` 与 `theme_shop_state`。 | ✅ |
| 18 | 排行榜 | 共享空间成员排行榜、专注自习室本地/服务端本周排行榜、服务端好友专注榜、好友申请审批/拒绝/取消/限流、全局专注榜、全局榜 WebSocket/SSE 实时事件、基础反作弊和服务端风控证据已落地；下一步补生产级持续风控和线上验证。 | 1-2 周 |
| 19 | 统计报告导出/分享图 | 已补统计页当前周期报告卡、Markdown、PNG 分享图、A4 PDF 视觉版/归档版/简报版/仪表版/时间线版五种模板、PDF 可检索中文文字层、系统分享面板直发、每日复盘/周报/月报/年报定时通知、动态通知摘要、自定义日/周/月/年推送时间，以及服务端 AI 个性化报告解读与 AI 历史保存。 | ✅ |
| 20 | 笔记富文本深化 | 已有 Markdown 工具栏/预览、笔记附件和图片内嵌预览；已补随手记搜索、置顶排序、活动/归档分段、滑动归档/恢复、卡片菜单管理和导出时保留置顶/归档状态；后续继续做真机文件选择和更复杂富文本编辑体验回归 | 1-2 周 |
| 21 | 图片/附件支持 | 已落地任务和笔记基础附件：任务详情可选择系统文件或手动添加链接/路径，图片附件内嵌预览，并随任务 JSON、备份和单模块导出保存；后续补云端文件同步、压缩和权限回归 | 1-2 周 |
| 22 | 第三方集成（API 开放） | 生态扩展 | 持续 |
| 23 | 强制屏蔽指定 App | Android DND 勿扰联动、严格专注惩罚、UsageStats 分心应用监控和 Accessibility 辅助功能拉回拦截已落地；VPN/设备管理级封锁、不同 ROM 保活和 iOS 同类能力仍需平台能力验证 | 2-3 周 |
| 24 | 从竞品导入数据 | 已落地迁移向导：支持备份页粘贴或选择本地 CSV/JSON 文件，按指尖时光、滴答清单、Todoist 或通用格式选择来源，预览模块数量、样例和解析提示，确认重复项跳过策略后再写入；兼容常见 Todoist/滴答清单/指尖时光字段并去重，可迁入待办、习惯、笔记、日历日程、纪念日、生日和倒数日；已补账号级 JSON 包络、项目/清单/标签嵌套继承、ID 映射导出结构、导入结果一键撤销和高级字段映射编辑；后续补真机文件选择回归 | ✅ |
| 25 | CSV/Excel 导出 | 已落地：备份页单模块导出提供待办、习惯、时间足迹、笔记、日记、纪念日和目标 CSV，Markdown 继续覆盖长文本模块。 | ✅ |
| 26 | 备份到云盘 | 已落地 WebDAV 云盘备份：支持 OpenList、坚果云、NAS 等通用 WebDAV 服务上传当前全量 JSON，并从云端同一路径合并或覆盖恢复；后续补 Google Drive/iCloud 原生授权 | ✅ |

### 投入产出比总结

```
投入最小、效果最大（推荐立即做）:
  → 自然语言日期解析 UI 回归、iOS Widget

投入中等、差异化显著（推荐近期做）:
  → 白噪音单音轨扩充、更多 Widget 类型、iOS Widget

投入大、生态价值高（推荐规划做）:
  → 第三方日历订阅、增量同步、社交专注
```

---

## 附录：竞品定位矩阵

```
                    功能丰富度 →
                低                     高
     ┌─────────────────────────────────────┐
  高 │                      │ 滴答清单      │
     │  Forest              │              │
专   │                      │   多仪 ★     │
注   │                      │              │
深   ├─────────────────────────────────────┤
度   │                      │ Todoist      │
     │                      │              │
  低 │  Microsoft To Do     │ 番茄TODO     │
     │                      │              │
     └─────────────────────────────────────┘
```

多仪在功能丰富度上已经达到或超过滴答清单，但在**单项功能的精打细磨**（自然语言、协作、白噪音深度）和**用户增长引擎**（社交、游戏化）上仍有明显差距。建议策略：**守住全场景一体化和数据主权两大护城河，重点补齐自然语言、日历订阅和 iOS Widget 三项核心短板**。
