# 多仪 v2 架构设计

本文档承接 `docs/design.md`，描述 v1 各系统落地后的补齐、增强与新增模块设计。
重点是**做什么、改什么**，已有且工作正常的部分不再复述。

---

## 1. 设计原则（延续 + 补充）

- **延续**：Flutter + Provider + SharedPreferences + FastAPI 后端。
- **延续**：业务规则在 core/services，页面只管展示。
- **延续**：调度、同步、迁移保持幂等。
- **新增**：所有用户可见文案通过 `BrandStrings` 注入，为 i18n 做准备。
- **新增**：新增特性通过 `FeatureFlags` 守护，灰度可回滚。
- **新增**：跨模块协作通过 `DomainEventBus` 解耦——Provider 之间不直接引用。

## 2. 当前架构摘要（v1 落地后状态）

```
lib/
  core/       domain_event_bus, calendar_aggregator, achievement_engine,
              feature_flags, brand_strings, habit_templates, ...
  models/     Todo, Habit, Goal, TimeEntry, Workspace, CalendarEvent, ...
  providers/  TodoProvider, HabitProvider, PomodoroProvider, GoalProvider,
              TimeAuditProvider, ShareProvider, AchievementProvider,
              CalendarProvider, CloudSyncProvider, ...
  services/   ReminderScheduler, PermissionHealthService, FocusSoundService,
              HomeWidgetService, HolidayCalendar, AlarmService, ...
  screens/    today, todo, habit, calendar, pomodoro, goal, time_audit,
              share, statistics, achievements, ...
  widgets/    calendar_event_sheet, reminder_plan_editor, quick_capture_fab,
              notification_health_card, eisenhower_matrix, ...
backend/      FastAPI auth/sync/admin/feedback/announcements
```

### 2.1 已落地的核心基础设施

| 组件 | 状态 | 说明 |
|------|------|------|
| DomainEventBus | 已实现 | 单例 broadcast StreamController，10 种事件类型 |
| ReminderScheduler | 已实现 | syncTodos/Goals (rule-based), syncHabits (alarm+fallback), syncAnniversaries (push), syncCountdowns (push), resyncAll |
| CalendarAggregator | 已实现 | 9 种来源聚合，冲突检测，统一排序 |
| CalendarEventSheet | 已实现 | 打开/完成/改期/调整时间/编辑/删除/打卡/开始专注 |
| PermissionHealthService | 已实现 | 通知/闹钟/弹屏/渠道/HyperOS/MIUI 分项检查 |
| AchievementEngine | 已实现 | 20 个规则，快照式求值 |
| AchievementProvider | 已实现 | 订阅 DomainEventBus，持久化 unlockedAt，解锁反馈和时光币奖励 |
| TimeEntry + TimeAuditProvider | 已实现 | 模型/CRUD/dedupeKey/分类，番茄/待办/日历入口写入 |
| Workspace + ShareProvider | 已实现 | 模型/角色/邀请码/评论/提及/负责人/排行榜 |
| FocusSoundService | 已实现 | 13 条单音轨，循环/淡入/淡出，自定义音轨播放 |
| HomeWidgetService | 已实现 | 10 个可见独立 Android 小组件数据推送和点击流 |
| HolidayCalendar | 已实现 | 2024-2026 内置数据，updateFrom 扩展口 |
| FeatureFlags | 已实现 | 4 个开关，全部默认 true |
| AudioService (deprecated) | 保留 | 转发到 FocusSoundService 的 shim |

### 2.2 当前剩余风险 / 待回归

1. CalendarEventSheet 已补本地日程编辑/删除、待办完成/改期/调整时间、习惯打卡、番茄开始/编辑和时间足迹调整；仍需更多真机路径和平台差异回归。
2. ReminderScheduler / NotificationService 已接入 snooze（稍后提醒）和通知点击 deep-link 分发；仍需真机回归确认端到端触发。
3. PermissionHealthService 已补 HyperOS/MIUI 分项、测试通知时间和 app resume 刷新；仍需 HyperOS/MIUI 真机确认系统级通知、弹屏、声音和后台行为。
4. TimeAuditProvider 已接入番茄自动记录、待办完成可选记录、日历 FAB 手动时间段和统计页时间分布；仍需真机路径与同步回归。
5. ShareProvider 后端 workspace API、邀请 UI、viewer 权限、任务负责人、空间/任务评论、@ 提及、成员排行榜、共享目标/本地共享日程和同步冲突记录已落地；仍需字段级冲突解释和多账号端到端回归。
6. AchievementProvider 已补解锁反馈、时光币、成长等级、挑战和奖励商店；后续可继续补更强的解锁动效和目标里程碑奖励。
7. 倒数日、纪念日、课程表与日历/提醒已有深度联动；仍需强提醒、农历生日和课程深链真机回归。
8. Android 已暴露 10 个可见独立小组件，待办勾选、快捷添加、习惯打卡和 deep-link 已接入；iOS 已补 10 个 WidgetKit kind、App Group 数据契约、Runner URL scheme、Xcode Extension target、待办详情/完成、快捷添加、习惯打卡、开始专注和底部导航 Link，仍缺开发者账号签名/App Group capability 真机确认、iOS 真机添加和 Android launcher 尺寸拖拽真机回归。
9. 中文自然语言日期解析、看板、专注 DND、专注标签统计、习惯弹性规则、周/月/年报告、通知栏快捷添加、Flutter gen-l10n/ARB 和 HolidayCalendar 2026 数据已落地；剩余以真机验证、逐页硬编码文案迁移和深度扩展为主。
10. TodoProvider/GoalProvider 已可注入 ReminderScheduler 并在关键写路径直接重同步；常规路径仍保留 main.dart listener 兜底。
11. deprecated AudioService shim 仍保留以兼容旧调用，后续确认无引用后可移除。

### 2.3 一级导航与专注入口

- Web 与原生客户端默认一级入口统一为「今日 / 待办 / 习惯 / 专注 / 我的」；宽屏使用侧栏，窄屏使用底栏。
- 专注复用 `MainShell` 中的 `PomodoroScreen`（tab 4）、`BrandStrings.navFocus` 和计时图标，页面切换沿用已访问页面保留机制。
- 默认入口最多五项；原生客户端的小组件可从「我的 → 更多应用」进入，仍可在导航设置中自定义显示与排序。
- `pref_focus_navigation_v1` 一次性将旧默认四项或包含小组件的旧默认五项升级为专注五项；保留原有排序及其他自定义组合，迁移后手动隐藏专注的选择可持久化。Web 原有导航迁移与小组件过滤继续生效。

### 2.4 Web 待办页面布局

- Web 待办页按「今日概要与提醒 → 自定义视图筛选 → 四象限 / 列表 / 看板页签 → 任务内容」上下排列，所有视图共享顶部筛选，不使用右侧筛选栏。
- 自定义视图始终保留清空按钮；无筛选时禁用，选中条件后启用，避免标题行和任务区域随选择状态改变高度。
- 快捷筛选与下拉筛选共用圆角、边框、文字和内边距，最小高度为 `DesignTokens.controlMinHeight`；选中态只改变配色，字号放大时内容可自然增高。
- 原生端保持现有页面分区，Web 宽屏继续沿用四象限四列、主导航和内容限宽规则。

### 2.5 习惯打卡与回顾

- 所有窗口尺寸使用同一组 `AppPageTabs`，将今日打卡与热度图分开，取消宽屏左右并列的双页面；内容最大宽度为 `habitWorkspaceMaxWidth`，宽屏今日卡片保留双列懒构建。
- 创建入口固定在页面右下角，桌面与手机共用 `AppCreateFab`，按钮带品牌文案，不再切换到宽屏标题栏。习惯空态只说明当前状态，不重复添加按钮或嵌套空白卡片。
- 今日页以本周概览、已有洞察、全部 / 待完成 / 已达标筛选和打卡卡片组织内容；筛选计数按当天生效与完成状态更新，继续复用原有打卡、撤回及侧滑编辑 / 结束 / 删除逻辑。
- 区分尚未建立习惯、今日无安排、当前筛选无结果三种状态；今日无安排时可直接转到热度图中的全部习惯分组与详情，不丢失历史或非生效日习惯。
- 热度图按需构建，保留十二周汇总与分类分组，说明性文案通过中英文 ARB 与 `I18n.tr` 提供；图格比例、主题字体与分组管理交互沿用现有契约。

### 2.6 目标与待办创建表单

- 目标编辑页与新建待办共用 `AppFormFieldTheme`：输入文字为 Noto Sans SC 常规字重 16px、标签 14px、输入区域至少 56px 高，使用相同内边距、圆角和焦点边框；名称与描述按内容自动增高。
- 两种表单共用 `creationFormMaxWidth`（720px）；新建目标通过 `showGoalCreateSheet` 从底部弹出，已有目标仍可进入编辑页，分组标题、提示及选择控件采用共享二级控件字号。
- 日期选择保持窄屏双列和短日期格式，控件最小高度与输入框一致；目标数值输入不再单独套紧凑装饰。
- 新建目标底部提供与待办相同样式的取消和主操作按钮，保存继续执行既有校验、权限判断与提交逻辑；新建弹窗不再包含独立页面 AppBar，编辑模式保留顶部保存和删除入口。

### 2.7 统一创建弹窗交互

- 页面级主创建入口统一位于右下角，并使用带文字的 `AppCreateFab`；待办、习惯、目标、笔记、日历、课程、纪念日、倒数日、时间足迹、反馈和共享空间共用该组件。今日页使用相同的页面右下角定位，保留当前子页对应的新建行为和长按快捷菜单。列表空态可保留居中引导；成员、邀请码等局部操作位于对应内容区，权限和批量模式继续决定按钮是否显示。
- 实体新建表单统一经 `showAppModalSheet` 与 `AppModalSheet` 呈现：初始为可用高度的 1/2 至 2/3、宽度最多 720px、底部贴合安全区；浏览内容可展开至可用全高，回到内容顶部后再向下拉收回。
- 共享容器唯一负责标题、拖柄、卡片、滚动与键盘避让；创建表单不嵌套 `Scaffold`、`Dialog`、独立分数高度或第二个外层滚动区。长编辑器使用受约束的内部视口。
- 点击遮罩、系统返回或取消关闭弹窗；确认保存前不创建实体，原有权限、字段校验、模板转换、提醒预检和服务端错误处理保持在各业务实现中。
- 今日页、目标管理的新建目标共用同一入口；通知 / 小组件快捷待办复用完整任务表单，快速笔记复用笔记创建编辑器。日程、位置提醒、共享空间、自习室 / 邀请码、模板及管理员创建表单沿用相同容器规则。
- 删除确认、提示信息、选择器、登录和独立 AI 工作流程保留各自语义，日记退役兼容入口不恢复创建能力。

### 2.8 共享视觉状态与动态效果

- 全主题使用随包提供的 Noto Sans SC 无衬线字体：正文 16px / 400、辅助文字 14px / 400、说明 12px、按钮 14px / 500、页面标题 20px / 600；统一使用设计 token，保留主题色、背景图与品牌文案。运行时字号为这些逻辑字阶乘以系统文字缩放和应用字号档位；应用档位可选 85% / 100% / 115%，只影响多仪内部文字，不修改系统设置。
- 视觉动画经 `AppMotion` 取值：轻量反馈 160ms、内容和 Web/桌面路由过渡 240ms，进入使用 `easeOutCubic`、退出使用 `easeInCubic`。Web/桌面路由采用淡入与最多 12px 的短位移；原生 iOS/macOS 与 Android 委托 Flutter 的原生切换器，保留原生时长、边缘返回与预测返回支持。
- 系统启用「减少动态效果」后，本轮共享路由、弹层、折叠、快捷创建、日期/时间反馈及接入的页面动画即时显示；时间滚轮直接定位，原生 iOS/macOS 仍保留返回手势容器。计时、通知、网络超时与提示停留时长不受视觉策略影响。
- 页签指示线始终采用线性移动；`AppPageSwitcher` 在动态效果设置变化后保留选择。
- `EmptyState` 以图标、主说明、可选补充说明和次级引导动作构成，不额外嵌套卡片；页面与区块拥有自己的表面。`ErrorState` 复用相同布局，以主题错误色标识，默认标题和重试支持中英文；管理员概览加载失败可原地重试。
- `LoadingState` 骨架取当前主题的表面色；系统减少动画或页面 `TickerMode` 不可见时停止持续动画，再次可见且允许动画时恢复。空态、错误态和加载说明在短屏与大字号下可滚动浏览。
- 目标、日历、时间足迹、共享空间和倒数日的主列表使用 `pageFabBottomPadding` 为右下角创建按钮保留末项空间；次级透明页面与页签保持品牌背景连续，避免重复背景层和滚动染色。

### 2.9 移动端输入与设置控件

- 应用根部覆盖 Flutter 的 `EditableTextTapOutsideIntent`：点击输入区域外的空白或控件清除焦点并隐藏键盘；输入框之间切换和输入区域内的辅助操作沿用 `TextFieldTapRegion` 语义。实际焦点脱离输入框后再次隐藏键盘，避免只失焦但 IME 留在屏幕。
- 全局 Material 滚动配置启用拖动收键盘；共享弹层打开、路由切换和一级导航切换清理离开页面的焦点，返回时不恢复已离开的输入状态。新页面主动聚焦的输入框仍可唤起键盘。
- 设置页的填充、描边、文字按钮使用相同最小高度、内边距和标准密度；同组菜单入口等宽，设置下拉框等宽。`AppSettingsTile` 不缩放尾部操作；窄屏和大字号时操作区移到文字下方，控件可随文本自然增高。

## 3. 目标架构（v2）

```
User Action / System Trigger
   |
Provider mutation ──> DomainEventBus ──> AchievementEngine
   |                        |                   |
   |                        |                   v
   |                        |           AchievementProvider
   |                        |               (overlay/snackbar)
   |                        |
   |                        +──> TimeAuditProvider (auto-record)
   |
   +──> CalendarAggregator ──> CalendarProvider
   |         |
   |         +──> CalendarActionRouter (complete/checkin/focus/reschedule/edit/delete)
   |
   +──> ReminderScheduler ──> NotificationSink / AlarmSink
   |         |                     |
   |         +──> Snooze handler   +──> Deep-link router
   |
   +──> CloudSyncProvider ──> Backend API
   |         |
   |         +──> WorkspaceSync
   |         +──> AchievementSync
   |
   +──> HomeWidgetService ──> Android Widget
            |
            +──> complete action / deep-link
```

### 3.1 新增 / 变更组件索引

| 编号 | 组件 | 类型 | 文件 |
|------|------|------|------|
| D1 | CalendarActionRouter | 新增 service | lib/core/calendar_action_router.dart |
| D1 | CalendarFilterChips | 新增 widget | lib/widgets/calendar_filter_chips.dart |
| D2 | SnoozeHandler | ReminderScheduler 扩展 | lib/services/reminder_scheduler.dart |
| D2 | DeepLinkRouter | 新增 service | lib/services/deep_link_router.dart |
| D3 | PermissionHealthService | 扩展 | lib/services/permission_health_service.dart |
| D4 | TimeAuditProvider | 扩展 | lib/providers/time_audit_provider.dart |
| D5 | ShareProvider | 扩展 | lib/providers/share_provider.dart |
| D6 | AchievementOverlay | 新增 widget | lib/widgets/achievement_overlay.dart |
| D8 | HomeWidgetService | 扩展 | lib/services/home_widget_service.dart |
| D9 | SmartDateParser | 新增 core | lib/core/smart_date_parser.dart |
| D10 | KanbanBoard | 新增 widget | lib/widgets/kanban_board.dart |
| D11 | FocusDndService | 新增 service | lib/services/focus_dnd_service.dart |
| D12 | Habit model | 扩展 | lib/models/habit.dart |
| D13 | ReportEngine | 新增 core | lib/core/report_engine.dart |
| D14 | QuickActionService | 新增 service | lib/services/quick_action_service.dart |
| D15 | L10n / AppLocalizations | 新增 core | lib/core/l10n/ |
| D16 | HolidayCalendar | 扩展 | lib/services/holiday_calendar.dart |

---

## 4. 各设计点详细设计

### D1: 日历枢纽增强

#### 4.1.1 CalendarActionRouter

CalendarEventSheet 当前直接 switch-case 调用各 Provider。随着操作增多（开始专注、
打卡确认），这些逻辑应提取到 CalendarActionRouter。

```dart
/// lib/core/calendar_action_router.dart
enum CalendarAction {
  complete,     // 完成待办 / 达成目标
  checkIn,      // 习惯打卡
  startFocus,   // 开始番茄钟（关联此事件）
  reschedule,   // 改期
  edit,         // 跳转编辑
  jumpToDetail, // 跳转详情
  delete,       // 删除
  addTimeEntry, // 添加时间记录
}

class CalendarActionRouter {
  /// 返回此事件支持的操作列表，UI 据此渲染按钮。
  static List<CalendarAction> actionsFor(CalendarEvent event) {
    final actions = <CalendarAction>[CalendarAction.jumpToDetail];
    switch (event.type) {
      case CalendarEventType.todo:
        if (!event.isCompleted) {
          actions.addAll([
            CalendarAction.complete,
            CalendarAction.startFocus,
            CalendarAction.reschedule,
          ]);
        }
        actions.add(CalendarAction.delete);
      case CalendarEventType.habit:
        if (!event.isCompleted) actions.add(CalendarAction.checkIn);
        actions.add(CalendarAction.delete);
      case CalendarEventType.goal:
        if (!event.isCompleted) {
          actions.addAll([
            CalendarAction.complete,
            CalendarAction.reschedule,
          ]);
        }
        actions.add(CalendarAction.delete);
      case CalendarEventType.pomodoro:
      case CalendarEventType.timeEntry:
        actions.addAll([CalendarAction.reschedule, CalendarAction.delete]);
      case CalendarEventType.anniversary:
      case CalendarEventType.countdown:
        actions.addAll([CalendarAction.reschedule, CalendarAction.delete]);
      case CalendarEventType.course:
        actions.add(CalendarAction.delete);
      case CalendarEventType.diary:
        actions.add(CalendarAction.edit);
    }
    return actions;
  }

  /// 执行操作，返回是否成功。
  static Future<bool> dispatch(
    BuildContext context,
    CalendarEvent event,
    CalendarAction action,
  ) async { /* 按 action+type 路由到对应 Provider */ }
}
```

改造 CalendarEventSheet：从硬编码 `_canComplete/_canReschedule/_canDelete` 改为
`CalendarActionRouter.actionsFor(event)` 动态生成按钮。

#### 4.1.2 类型过滤 Chips

```dart
/// lib/widgets/calendar_filter_chips.dart
class CalendarFilterChips extends StatelessWidget {
  final Set<CalendarEventType> selected;
  final ValueChanged<Set<CalendarEventType>> onChanged;
  // 渲染 FilterChip 列表，每种类型对应一个
}
```

CalendarProvider 增加 `Set<CalendarEventType> activeFilters` 字段，
CalendarAggregator.buildEvents() 的结果再经 filter 后输出给 UI。

#### 4.1.3 排序共享

TodayScreen 和 CalendarScreen 已共享 CalendarAggregator。确认两处使用相同的
`_compareEvents` 即可，无需额外改动。

### D2: 多提醒 v2 补齐

#### 4.2.1 Snooze 支持

Android notification action button 回调路径：

```
用户点 "稍后 5分钟" → NotificationService.onAction(id, 'snooze_5')
    → ReminderScheduler.snooze(notificationId, Duration(minutes: 5))
        → 取消当前通知
        → 重新 scheduleOnce(id + '_snooze', when: now + 5min, ...)
```

NotificationService 负责将通知 action / deep-link 统一转入稍后提醒：

```dart
/// 稍后提醒：取消原通知，延后重新下发。
Future<void> snooze({
  required int id,
  required String title,
  required String body,
  required Duration delay,
  String? payload,
}) async { ... }
```

通知注册时添加 action buttons（仅 Android）：

```dart
// local_notifications_io.dart
AndroidNotificationAction('snooze_5', '5分钟后'),
AndroidNotificationAction('snooze_10', '10分钟后'),
AndroidNotificationAction('snooze_30', '30分钟后'),
```

#### 4.2.2 通知点击 Deep-link

已有 payload 格式 `duoyi://todo/{id}`、`duoyi://habit/{id}?confirm=1`、
`duoyi://goal/{id}`、`duoyi://countdown/{id}`。

新增 DeepLinkRouter 统一处理：

```dart
/// lib/services/deep_link_router.dart
class DeepLinkRouter {
  /// 从 notification tap 或 widget click 的 URI 导航到对应页面。
  static Future<void> handle(BuildContext context, Uri uri) async {
    switch (uri.host) {
      case 'todo':
        final id = uri.pathSegments.firstOrNull;
        if (id == null) return;
        final confirm = uri.queryParameters['confirm'] == '1';
        if (confirm) {
          // 弹出确认完成对话框
        } else {
          await TodayDetailRouter.open(context, TodaySectionKind.todos, id: id);
        }
      case 'habit':
        // ...
      case 'goal':
        // ...
      case 'countdown':
        // ...
      case 'calendar':
        // 导航到日历并选中日期
    }
  }
}
```

main.dart 中统一注册 notification tap handler 和 HomeWidget click handler，
都路由到 DeepLinkRouter.handle。

### D3: 通知健康补齐

#### 4.3.1 HyperOS 检测

PermissionHealthService 已有 `device?.isXiaomiLike`。需扩展 `AndroidDeviceInfoLite`：

```dart
/// platform_info_io.dart 中 AndroidDeviceInfoLite 扩展
bool get isHyperOS {
  // HyperOS 的 Build.VERSION.INCREMENTAL 包含 'OS1.' 前缀
  // 或 SystemProperties 'ro.mi.os.version.name' 非空
  return brand.toLowerCase() == 'xiaomi' &&
      (incrementalVersion.startsWith('OS1.') ||
       miOsVersion.isNotEmpty);
}
```

PermissionHealthService.check() 中，当 `isHyperOS` 为 true 时替换检查项文案：

```dart
if (device?.isHyperOS == true) {
  // 替换"小米自启动"为"HyperOS 自启动"
  // 添加 HyperOS 专属项：通知类别管理
}
```

#### 4.3.2 测试通知结果日志

```dart
/// permission_health_service.dart 扩展
Future<TestNotificationResult> sendTestNotification() async {
  final id = _idFor('test_${DateTime.now().millisecondsSinceEpoch}');
  final sentAt = DateTime.now();
  await notif.scheduleOnce(
    id: id,
    title: '测试通知',
    body: '如果你看到了这条通知，说明通知功能正常',
    when: sentAt.add(const Duration(seconds: 2)),
  );
  return TestNotificationResult(id: id, sentAt: sentAt);
}

class TestNotificationResult {
  final int id;
  final DateTime sentAt;
  // UI 层可记录用户是否确认收到
}
```

#### 4.3.3 App Resume 自动刷新

在独立通知设置页 `_NotificationSettingsScreenState` 中混入 `WidgetsBindingObserver`：

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // 重新执行 PermissionHealthService.check()
    _refreshHealth();
  }
}
```

### D4: 时间足迹集成

#### 4.4.1 PomodoroProvider 自动写入

`PomodoroProvider` 完成专注后由 `_persistCompletedSession()` 调用
`TimeAuditProvider.recordPomodoroSession()` 自动写入；编辑和删除会话同步更新
对应的时间记录，`pomodoro:<sessionId>` 为去重键。

- 任务选择优先展示当前账号的未完成待办，可搜索任务或子任务，展开后直接选择子任务；选择只关联专注，不改变待办完成状态。预设和手动输入保留为补充入口。
- `PomodoroState` 与 `PomodoroSession` 保存可选 `todoId`、`subtaskId`、`todoTitle`（父名称快照）；`taskName` 为选中对象名称。运行快照、完成结算和 JSON 往返均保留关联。旧记录缺字段继续按自由名称展示，不按同名猜测待办关联。
- 子任务的历史展示及自动时间记录使用“父任务 / 子任务”。手动重命名历史会话会解除原 ID 关联；任务改名按稳定 ID 汇总，任务删除后仍以快照展示。
- 时光足迹的“任务专注”卡随周／月／年选定周期过滤 `PomodoroSession.endTime`，仅计专注会话；按父任务 ID 汇总时长与次数，展开查看子任务及直接专注父任务的部分。每次会话只计入总量一次，先累加秒数再格式化。休息会话不计入，手动名称和未关联记录独立分组。

#### 4.4.2 待办完成可选记录

TodayScreen / TodoScreen / CalendarEventSheet / `duoyi://action/complete_todo`
统一调用 `completeTodoWithOptionalTimeRecord()`，在完成待办后弹出可选的耗时记录弹层：

```dart
// 不在 Provider 层弹 UI，保持关注点分离。
// 完成入口统一复用 completeTodoWithOptionalTimeRecord()
// → 显示可选的"记录耗时？"底部弹层 → 用户确认后调用 TimeAuditProvider.add()
```

#### 4.4.3 统计页时间分布

StatisticsScreen 增加时间分布 Tab：

```dart
// 饼图：按 TimeEntryCategory 分组的总时长占比
// 柱状图：过去 7 天每天的时间分布
// 数据来源：TimeAuditProvider.entries 按日期和分类聚合
```

#### 4.4.4 日历添加时间记录

CalendarScreen FAB 已提供“记录一段时间”入口，直接写入 TimeAuditProvider：

```dart
// _showQuickAddTimeEntry()
// 预填所选日期，选择开始时间、分类、时长和备注
// 保存为 source = TimeEntrySource.manual
```

### D5: 共享空间补齐

#### 4.5.1 后端 API 验证

需验证以下端点功能正常：

```
POST   /api/workspaces                    创建空间
GET    /api/workspaces                    列出空间
POST   /api/workspaces/{id}/invites       创建邀请
POST   /api/invites/{code}/accept         接受邀请
PATCH  /api/workspaces/{id}/members/{uid} 修改角色
DELETE /api/workspaces/{id}/members/{uid} 移除成员
```

#### 4.5.2 邀请流程 UI

ShareScreen 新增邀请流程：

```dart
// 创建邀请码 → 显示可复制的 code / 二维码
// 接受邀请 → 输入 code → 调用 POST /api/invites/{code}/accept
// 结果展示 → 加入成功 / 已过期 / 无效
```

#### 4.5.3 共享标志

列表项 UI 中，当对象的 `workspaceId` 不为 `'private'` 时，在标题右侧显示
共享图标 badge：

```dart
if (item.workspaceId != 'private')
  Icon(Icons.people_outline, size: 14, color: cs.outline),
```

#### 4.5.4 Viewer 角色执行

ShareProvider 已有 `Workspace.roleFor(userId)`。在 UI 层：

```dart
final role = shareProvider.currentRole(workspaceId);
// role == WorkspaceRole.viewer 时：
//   - 隐藏编辑/删除按钮
//   - TextField 设为 readOnly
//   - FAB 隐藏
```

### D6: 成就管线补齐

#### 4.6.1 DomainEventBus 事件发布补全

当前 providers 中 DomainEventBus.publish 的调用点不够全面。需确保：

| Provider | 事件 | 触发时机 |
|----------|------|----------|
| TodoProvider | todoCreated | addTodo() |
| TodoProvider | todoCompleted | toggleTodo() 完成时 |
| HabitProvider | habitCreated | addHabit() |
| HabitProvider | habitCheckedIn | incrementHabit() |
| PomodoroProvider | pomodoroCompleted | _completeSession() |
| GoalProvider | goalCreated | add() |
| GoalProvider | goalAchieved | setStatus(achieved) |
| GoalProvider | goalMilestoneCompleted | completeMilestone() |
| DiaryProvider | diaryWritten | add() |
| ThemeProvider | themeSwitched | setTheme() |

每处 publish 格式：

```dart
DomainEventBus.instance.publish(DomainEvent(
  type: DomainEventType.todoCompleted,
  objectId: todo.id,
  metadata: {'title': todo.title},
));
```

#### 4.6.2 解锁 Overlay

新增全局 Overlay widget，在 `AchievementProvider` 检测到 `newlyUnlocked` 时触发：

```dart
/// lib/widgets/achievement_overlay.dart
class AchievementUnlockOverlay {
  /// 从任意 Navigator 上层展示一个 3 秒的滑入/滑出横幅。
  static void show(BuildContext context, Achievement achievement) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AchievementBanner(
        achievement: achievement,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}
```

AchievementProvider._rebuildSnapshots() 中的 `newlyUnlocked` 循环已调用
`_notificationService?.notifyAchievementUnlocked()`。新增回调机制：

```dart
// AchievementProvider 增加回调
VoidCallback? onUnlocked; // 由 MaterialApp builder 注册
// _rebuildSnapshots 中：
for (final achievement in newlyUnlocked) {
  _notificationService?.notifyAchievementUnlocked(achievement);
  _pendingOverlays.add(achievement);
}
if (_pendingOverlays.isNotEmpty) onUnlocked?.call();
```

#### 4.6.3 成就同步

CloudSyncProvider 的 sync payload 增加 `achievement_states` collection：

```json
{
  "achievement_states": [
    {"id": "first_todo", "unlocked_at": "2026-05-10T08:30:00Z"},
    {"id": "todo_10", "unlocked_at": null, "current": 7}
  ]
}
```

合并策略：`unlocked_at` 取最早（非空优先）；`current` 取最大。

### D7: 课程/纪念日深度集成（倒数日恢复可见）

#### 4.7.1 倒数日可见边界

倒数日作为当前版本的可见主流程：提供新增入口，进入搜索、日历聚合、导出和深链。
旧数据继续保留兼容读取/编辑路径，避免历史数据丢失。

#### 4.7.2 纪念日 Alarm 支持

Anniversary 模型增加 `ReminderKind kind` 字段（默认 push）。
ReminderScheduler.syncAnniversaries() 按 kind 分发：

```dart
if (a.kind == ReminderKind.alarm) {
  await _dispatch(kind: ReminderKind.alarm, payload: ...);
} else {
  await notif.scheduleAnniversary(/* 现有 */);
}
```

#### 4.7.3 课程 Deep-link

CalendarEventSheet 中 course 类型的 `_open` 已导航到
`TodayDetailRouter.open(context, TodaySectionKind.courses, id: sourceId)`。
确认 TodayDetailRouter 正确处理 course 跳转即可。

若从通知点击进入，DeepLinkRouter 增加 `case 'course':` 处理。

### D8: 小组件增强

#### 4.8.1 Widget 完成操作

Android 端 `DuoyiTodoWidgetProvider.kt` 在待办项旁增加完成按钮：

```kotlin
// 点击完成 → 发送 Intent action = "com.duoyi.COMPLETE_TODO"
//           extra = todoId
// BroadcastReceiver 接收后：
//   1. 调用 HomeWidget.getWidgetData("todo_top3_1_id") 获取 id
//   2. 通过 MethodChannel 调用 Flutter 端 TodoProvider.toggleTodo(id)
//   3. 触发 HomeWidgetService.push() 刷新
```

Flutter 端注册 background callback：

```dart
// main.dart
HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);

@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host == 'complete-todo') {
    final todoId = uri!.pathSegments.first;
    // 读取 SharedPreferences → toggle todo → push widget update
  }
}
```

#### 4.8.2 Widget Deep-link

HomeWidgetService.widgetClickedStream 已存在。在 main.dart 中：

```dart
HomeWidgetService.widgetClickedStream.listen((uri) {
  if (uri != null) DeepLinkRouter.handle(navigatorKey.currentContext!, uri);
});
```

#### 4.8.3 数据变更刷新

各 Provider mutation 后已在 main.dart listener 中调用 `HomeWidgetService.push()`。
确认所有写操作路径（包括新增的 background callback）都触发 push。

### D9: 智能日期解析

#### 4.9.1 SmartDateParser

```dart
/// lib/core/smart_date_parser.dart
class ParsedDateTime {
  final DateTime? date;
  final TimeOfDay? time;
  final String cleanedText; // 移除日期表达后的纯文本
  final bool hasDate;
  final bool hasTime;
}

class SmartDateParser {
  /// 从中文自然语言中提取日期时间。
  ///
  /// 支持的表达：
  /// - 今天、明天、后天、大后天
  /// - 下周一..下周日、这周一..这周日
  /// - X月X日、X号
  /// - 上午/下午/晚上 + 数字点
  /// - "3点"、"15:30"、"下午3点半"
  ///
  /// 示例：
  /// - "明天下午3点开会" → date=tomorrow, time=15:00, cleanedText="开会"
  /// - "下周五提交报告" → date=nextFriday, time=null, cleanedText="提交报告"
  static ParsedDateTime parse(String input, {DateTime? now}) {
    now ??= DateTime.now();
    // 正则匹配链：日期 → 时间 → 清理
    // ...
  }
}
```

正则模式（核心）：

```dart
// 日期
static final _datePatterns = [
  RegExp(r'今天'),
  RegExp(r'明天'),
  RegExp(r'后天'),
  RegExp(r'大后天'),
  RegExp(r'(下|这)周([一二三四五六日天])'),
  RegExp(r'(\d{1,2})月(\d{1,2})[日号]?'),
  RegExp(r'(\d{4})[年/\-](\d{1,2})[月/\-](\d{1,2})[日号]?'),
];

// 时间
static final _timePatterns = [
  RegExp(r'(上午|下午|晚上|早上|中午|傍晚)?(\d{1,2})[点时:：](\d{1,2})?[分]?(半)?'),
  RegExp(r'(\d{1,2}):(\d{2})'),
];
```

#### 4.9.2 QuickCaptureFab 集成

`_quickTodo()` 中，用户输入文本后：

```dart
final parsed = SmartDateParser.parse(ctrl.text.trim());
final todo = TodoItem(
  title: parsed.cleanedText.isNotEmpty ? parsed.cleanedText : ctrl.text.trim(),
  date: parsed.date ?? DateTime.now(),
  dueDate: parsed.hasTime && parsed.date != null
      ? DateTime(parsed.date!.year, parsed.date!.month, parsed.date!.day,
                 parsed.time!.hour, parsed.time!.minute)
      : null,
);
```

### D10: 看板视图

#### 4.10.1 数据模型

看板不引入新模型——复用 TodoItem 的分组字段：

```dart
// TodoItem 扩展（如尚未有）：
// String? kanbanColumn; // 看板列名，默认按 EisenhowerQuadrant 映射
// int kanbanOrder;      // 列内排序
```

或完全基于现有字段动态分组：

```dart
enum KanbanGroupBy {
  quadrant,    // 按四象限
  priority,    // 按优先级
  dueStatus,   // 未到期 / 今天 / 过期 / 无截止
  custom,      // 自定义列
}
```

#### 4.10.2 KanbanBoard Widget

```dart
/// lib/widgets/kanban_board.dart
class KanbanBoard extends StatefulWidget {
  final List<TodoItem> todos;
  final KanbanGroupBy groupBy;
  final ValueChanged<TodoItem> onTodoUpdated;
  // ...
}
```

核心交互：
- 横向滚动 N 列
- 每列内垂直列表
- 长按拖拽跨列移动（更新对应字段）
- 列头显示计数

TodoScreen 增加第三种视图切换（四象限 / 列表 / 看板），通过
`BrandStrings` 增加 `todoKanbanView` 字段。

#### 四象限视觉语义与首页间距

四象限使用共享的`todoQuadrantColor`映射和`DesignTokens.quadrantQ1`至`quadrantQ4`：Q1紧急且重要为红色`#E53935`，Q2重要不紧急为紫色`#8E5CC6`，Q3紧急不重要为黄色`#F6A339`，Q4不紧急不重要为绿色`#43A047`。首页标题圆点、待办页四象限和列表、日历的象限标记以及统计卡片使用同一映射；象限名称继续保留，不仅依赖颜色区分。完成状态色、清单分类色与这套象限色独立。

首页的完成控件或子任务进度与右侧内容列之间使用`DesignTokens.homeItemLeadingGap`（32px）。象限圆点使用`homeQuadrantDotSize`（10px），与任务名之间使用`homeQuadrantTitleGap`（8px）；圆点距左侧控件边界至少12px。任务标题、清单标签、子任务及目标页签标题保留对应的对齐关系。

### D11: 专注模式增强

#### 4.11.1 Android DND 集成

```dart
/// lib/services/focus_dnd_service.dart
class FocusDndService {
  static final FocusDndService instance = FocusDndService._();
  FocusDndService._();

  /// 开启免打扰（需 NOTIFICATION_POLICY_ACCESS 权限）。
  Future<bool> enableDnd() async {
    if (!PlatformInfo.isAndroid) return false;
    // MethodChannel 调用 Android NotificationManager.setInterruptionFilter
    return await _channel.invokeMethod<bool>('enableDnd') ?? false;
  }

  /// 恢复原始免打扰状态。
  Future<void> restoreDnd() async {
    if (!PlatformInfo.isAndroid) return;
    await _channel.invokeMethod<void>('restoreDnd');
  }

  /// 检查是否有 DND 权限。
  Future<bool> hasDndAccess() async {
    if (!PlatformInfo.isAndroid) return false;
    return await _channel.invokeMethod<bool>('hasDndAccess') ?? false;
  }
}
```

PomodoroProvider 扩展：

```dart
// 配置项
bool enableDndDuringFocus = false;

// start() 中：
if (enableDndDuringFocus) await FocusDndService.instance.enableDnd();

// _completeSession() / cancel() 中：
if (enableDndDuringFocus) await FocusDndService.instance.restoreDnd();
```

#### 4.11.2 专注标签

PomodoroSession 模型增加：

```dart
List<String> tags; // 如 ['工作', '编程', '阅读']
```

标签在开始专注时选择，统计页按标签分组显示时长。

#### 4.11.3 白噪音分类

FocusSoundService._assetMap 当前 9 个音轨。增加分类元数据：

```dart
class SoundTrack {
  final String id;
  final String asset;
  final String label;
  final SoundCategory category;
}

enum SoundCategory { nature, ambient, noise }

static const List<SoundTrack> tracks = [
  SoundTrack(id: 'rain', asset: '...', label: '雨声', category: SoundCategory.nature),
  SoundTrack(id: 'cafe', asset: '...', label: '咖啡馆', category: SoundCategory.ambient),
  SoundTrack(id: 'brown_noise', asset: '...', label: '棕噪', category: SoundCategory.noise),
  // ...
];
```

UI 按 category 分组显示音轨选择器。

### D12: 习惯增强

#### 4.12.1 灵活频次

Habit 模型当前有 `activeWeekdays` (0..6) 和 `weeklyTarget`。扩展频次策略：

```dart
enum HabitFrequency {
  daily,        // 每天（现有默认）
  weeklyCount,  // 每周 N 次（不指定哪几天）
  specificDays,  // 指定星期几（现有 activeWeekdays）
  interval,      // 每 N 天一次
}

// Habit 模型增加：
HabitFrequency frequency = HabitFrequency.specificDays;
int intervalDays = 1; // frequency == interval 时生效
```

HabitProvider 的"今日是否应打卡"判定逻辑：

```dart
bool shouldCheckInToday(Habit h, DateTime today) {
  switch (h.frequency) {
    case HabitFrequency.daily:
      return true;
    case HabitFrequency.weeklyCount:
      // 本周已完成次数 < weeklyTarget
      return _weeklyCompletions(h, today) < h.weeklyTarget;
    case HabitFrequency.specificDays:
      return h.activeWeekdays.contains(today.weekday - 1);
    case HabitFrequency.interval:
      // 距上次打卡 >= intervalDays
      return _daysSinceLastCheckIn(h, today) >= h.intervalDays;
  }
}
```

#### 4.12.2 习惯分组

Habit 模型已有 `String? category`。HabitScreen 增加按 category 分组的折叠列表视图：

```dart
// 无 category 的归入"未分类"
// 用户可在习惯编辑页选择或创建 category
// category 列表由当前所有习惯的 category 集合动态生成
```

#### 4.12.3 习惯模板扩展

HabitTemplates 已有 10 个模板。增加频次信息：

```dart
class HabitTemplate {
  // ... 现有字段 ...
  final HabitFrequency frequency;
  final int weeklyTarget;
  final List<int> activeWeekdays;
}
```

模板选择页按 category 分组展示，选中后预填到新建习惯表单。

### D13: 数据可视化增强

#### 4.13.1 ReportEngine

```dart
/// lib/core/report_engine.dart
class WeeklyReport {
  final DateTime weekStart;
  final int todosCompleted;
  final int todosCreated;
  final int habitCheckIns;
  final int habitMissed;
  final int focusMinutes;
  final int focusSessions;
  final int diaryCount;
  final int goalsProgressed;
  final Map<TimeEntryCategory, int> timeDistribution; // 秒数
  final double productivityScore; // 0..100
}

class ReportEngine {
  /// 生成指定周的周报。
  static WeeklyReport weeklyReport({
    required DateTime weekStart,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<DiaryEntry> diaries,
    required List<GoalItem> goals,
    required List<TimeEntry> timeEntries,
  }) { /* ... */ }

  /// 生成年度总结。
  static AnnualReport annualReport({ /* 类似参数 */ }) { /* ... */ }
}
```

#### 4.13.2 统计页扩展

StatisticsScreen 新增 Tabs：

```
现有: 待办 | 习惯 | 专注 | 日程
新增: 时间 | 周报 | 年报
```

- 时间 Tab：饼图（分类占比）+ 柱状图（每日时长）
- 周报 Tab：卡片式周报，左右滑动切换周
- 年报 Tab：年度热力图 + 关键指标 + 趋势折线

#### 4.13.3 跨模块分析

```dart
// 示例分析：番茄钟关联待办的完成率
// 有关联 focus session 的 todo 完成率 vs 无关联的完成率
// 在周报中展示
```

### D14: 快捷操作

#### 4.14.1 通知栏快速添加

Android Notification 常驻通知（可选）：

```dart
/// lib/services/quick_action_service.dart
class QuickActionService {
  /// 显示一条持久通知，带"快速待办"和"开始专注"按钮。
  static Future<void> showQuickActions() async {
    await LocalNotifications.instance.showOngoing(
      id: _quickActionNotifId,
      title: '多仪',
      body: '点击快速添加',
      actions: [
        AndroidNotificationAction('quick_todo', '添加待办'),
        AndroidNotificationAction('quick_focus', '开始专注'),
      ],
    );
  }
}
```

#### 4.14.2 Widget 快速添加

HomeWidgetService 在独立待办小组件中增加"+"按钮：

```kotlin
// 点击"+" → 启动 Flutter Activity，传入 intent extra quickAdd=true
// Flutter 端检测后直接弹出 _quickTodo 对话框
```

#### 4.14.3 模板快速创建

QuickCaptureFab 增加"从模板创建"子按钮：

```dart
_mini(
  icon: Icons.copy_all,
  label: '从模板',
  color: Colors.teal,
  onTap: _quickFromTemplate,
),
```

`_quickFromTemplate()` 弹出模板选择器（TodoTemplates / HabitTemplates），
选中后一键创建。

### D15: 国际化支持

#### 4.15.1 架构

采用 Flutter 官方 `flutter_localizations` + `intl` + ARB 文件：

```
lib/core/l10n/
  app_en.arb         英文翻译
  app_zh.arb         中文翻译（从 BrandStrings.defaultBrand 提取）
  l10n.dart          生成的 AppLocalizations
```

#### 4.15.2 BrandStrings 与 L10n 的关系

BrandStrings 是品牌/主题皮肤的文案，L10n 是语言翻译。两者正交：

```
选择语言 = en → 基础文案用英文 AppLocalizations
选择皮肤 = re0 → 覆盖部分文案用 BrandStrings.re0

优先级：BrandStrings > AppLocalizations
```

实现策略：

```dart
// BrandStrings 增加可选字段 locale:
// BrandStrings.defaultBrand → 使用 AppLocalizations（不硬编码）
// BrandStrings.re0 等皮肤 → 继续硬编码中文（皮肤本身就是中文文化语境）
```

#### 4.15.3 迁移步骤

1. 提取所有 hardcoded 中文到 ARB
2. 生成 AppLocalizations
3. BrandStrings.defaultBrand 改为从 AppLocalizations 读取
4. 各 screen/widget 中直接使用的中文改为 AppLocalizations
5. 皮肤 BrandStrings 保持不变（皮肤本身是文化主题，不翻译）

### D16: 节假日 2026+ 数据

#### 4.16.1 内置 2026 数据

```dart
// holiday_calendar.dart _kBuiltinHolidays 增加：
2026: HolidayYear(
  holidays: <String>{
    // 元旦
    '01-01', '01-02', '01-03',
    // 春节（2026 春节 2/17）
    '02-15', '02-16', '02-17', '02-18', '02-19', '02-20', '02-21',
    // 清明
    '04-05', '04-06', '04-07',
    // 劳动节
    '05-01', '05-02', '05-03', '05-04', '05-05',
    // 端午（2026 端午 6/19）
    '06-19', '06-20', '06-21',
    // 中秋（2026 中秋 9/25）+ 国庆
    '09-25',
    '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07', '10-08',
  },
  workMakeupDays: <String>{
    '02-14', '02-22',
    '04-26',
    '09-27',
    '10-10',
  },
),
```

注意：2026 年国务院公告尚未发布，以上为基于历史规律的预估。
正式数据发布后需更新，或通过 `updateFrom` 动态注入。

#### 4.16.2 后端 API 推送

```
GET /api/holidays/{year}
响应: { "year": 2026, "holidays": ["01-01", ...], "work_makeup_days": ["02-14", ...] }
```

CloudSyncProvider 在同步时检查是否有新年度数据，有则调用
`HolidayCalendar.updateFrom(year, data)`。

### D17: ReminderScheduler 集成修复

#### 4.17.1 问题

TodoProvider 和 GoalProvider 当前使用动态 dispatch 回退——在某些路径下可能
绕过 ReminderScheduler 直接调用 NotificationService。

#### 4.17.2 修复

确保 TodoProvider 的所有写操作（add/update/toggle/delete）结束后调用：

```dart
// TodoProvider
void _afterMutation() {
  notifyListeners();
  // 直接调用 ReminderScheduler（由 main.dart 注入引用）
  _reminderScheduler?.syncTodos(todos);
}
```

同理 GoalProvider：

```dart
void _afterMutation() {
  notifyListeners();
  _reminderScheduler?.syncGoals(goals);
}
```

移除 main.dart 中通过 listener 间接调用的旧路径，保持单一调用点。

### D18: AudioService 清理

#### 4.18.1 删除 deprecated shim

1. 删除 `lib/services/audio_service.dart`
2. 全局搜索 `AudioService` 引用，替换为 `FocusSoundService.instance`
3. 如果有第三方插件引用，在 CHANGELOG 中注明 breaking change

#### 4.18.2 验证

确认以下路径都使用 FocusSoundService：

- PomodoroProvider._sound
- PomodoroScreen 白噪音选择器
- 任何其他可能引用旧 AudioService 的位置

---

## 5. 迁移设计

### 5.1 Habit 频次迁移

- 现有习惯默认 `frequency = HabitFrequency.specificDays`
  （因为已有 `activeWeekdays`）。
- `weeklyTarget` 已存在，`frequency = weeklyCount` 时才启用其语义。
- SharedPreferences 序列化增加 `frequency` 和 `intervalDays` 字段；
  旧数据缺失时用默认值，无需批量迁移。

### 5.2 CountdownItem / Anniversary kind 迁移

- 新增 `ReminderKind kind` 字段，默认 `push`。
- 旧数据无此字段，fromJson 默认为 push。
- 用户在编辑页手动切换后存入新字段。

### 5.3 BrandStrings → L10n 迁移

- 第一步：仅增加 ARB 文件和 AppLocalizations，不动现有代码。
- 第二步：BrandStrings.defaultBrand 改为从 AppLocalizations 取值。
- 第三步：各 screen 中的 hardcoded 中文逐页替换。
- 皮肤 BrandStrings 不迁移。

### 5.4 AudioService 清理迁移

- 先 grep 确认无生产代码直接 import audio_service.dart。
- 删除文件。
- CI 构建验证通过。

### 5.5 PomodoroSession tags 迁移

- 新增 `List<String> tags` 字段，默认空列表。
- 旧 session JSON 无此字段，fromJson 默认为 `[]`。

### 5.6 HolidayCalendar 2026 数据

- 内置预估数据立即可用。
- 后端 API 上线后，客户端在同步时自动覆盖。
- 正式公告发布后更新内置数据。

---

## 6. 测试设计

### 6.1 单元测试

| 测试目标 | 覆盖范围 |
|----------|----------|
| SmartDateParser | 20+ 中文日期表达，边界日期，时间提取，文本清理 |
| CalendarActionRouter | 每种 event type 的 actionsFor 正确性 |
| ReportEngine | weeklyReport 聚合正确性，空数据 |
| HolidayCalendar 2026 | isHoliday / isWorkMakeupDay 抽样验证 |
| Habit frequency | shouldCheckInToday 四种模式 |
| Snooze | snooze 后重新调度时间正确 |
| DeepLinkRouter | 各种 URI scheme 解析 |
| TimeAuditProvider.addFromPomodoro | 幂等去重 |
| AchievementProvider overlay | newlyUnlocked 正确检测 |

### 6.2 属性测试

| 属性 | 描述 |
|------|------|
| SmartDateParser 往返 | parse(format(date)) 还原原始 date |
| Snooze 幂等 | 连续 snooze 不产生重复通知 |
| CalendarFilter 恒等 | filter(all_types) == no_filter |
| Kanban 拖拽一致性 | 拖拽后 todo.kanbanColumn 与目标列一致 |
| Habit frequency 覆盖 | weeklyCount=7 等价于 daily 在正常周 |

### 6.3 Widget 测试

| 测试目标 | 场景 |
|----------|------|
| CalendarFilterChips | 选中/取消/全选/全不选 |
| KanbanBoard | 渲染列数、拖拽回调 |
| AchievementOverlay | 显示/自动消失/多个排队 |
| QuickCaptureFab + SmartDateParser | 输入含日期文本后预填日期 |

### 6.4 集成测试

| 测试目标 | 场景 |
|----------|------|
| Pomodoro → TimeEntry | 完成专注后 TimeAuditProvider 自动新增 |
| Todo 完成 → Achievement | 完成第 10 个 todo 后 achievement 解锁 |
| Widget 完成 | Android widget background callback 正确 toggle |
| Snooze 端到端 | 通知 action → ReminderScheduler.snooze → 延后触发 |
| Share invite 流程 | 创建邀请码 → 另一用户接受 → 成员列表更新 |

### 6.5 手工回归

- Android 13+ 通知权限流程
- Android 12+ 精准闹钟权限流程
- 小米/HyperOS 自启动、后台、锁屏、电池
- DND 权限请求和恢复
- 小组件添加、显示、点击、完成操作
- 各皮肤下看板视图文案正确
- 通知 snooze 按钮显示和回调
- 专注模式白噪音不中断（锁屏后继续）

---

## 7. 风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| SmartDateParser 误解析 | 用户预期外的日期 | 解析结果在 UI 预览确认，用户可手动修正 |
| Android DND 权限被厂商限制 | DND 功能不可用 | hasDndAccess() 前置检查，降级为不开启 |
| 2026 节假日预估不准 | 日历标注错误 | updateFrom 动态覆盖，正式公告后更新内置 |
| i18n 工作量大 | 延期 | 分阶段：先基础框架，后逐页替换 |
| 看板拖拽性能 | 大量 todo 时卡顿 | 虚拟化列表，限制单列显示数 |
| Widget background callback | 进程被系统 kill 后无法执行 | Fallback 到打开 App 后同步状态 |
| 共享空间后端稳定性 | 同步失败 | 离线模式优先，sync 失败不阻塞本地操作 |
| AudioService 清理遗漏 | 编译失败 | CI 全量构建验证 |
| Snooze 通知 id 冲突 | 覆盖正常通知 | snooze 使用独立 id namespace |
| Habit frequency 变更后历史数据 | 统计口径不一致 | 频次变更仅影响未来判定，历史打卡数据不回溯 |

---

## 8. 分阶段交付

### Phase 0：基础修复与清理
- D17: ReminderScheduler 集成修复
- D18: AudioService 清理
- D16: HolidayCalendar 2026 数据
- 预估：1 周

### Phase 1：日历与通知补齐
- D1: CalendarActionRouter + 过滤 Chips
- D2: Snooze 支持 + DeepLinkRouter
- D3: 通知健康补齐（HyperOS + 测试通知 + resume 刷新）
- 预估：2 周

### Phase 2：时间足迹闭环
- D4: PomodoroProvider 自动写入 + 待办完成记录 + 统计时间分布
- 预估：1 周

### Phase 3：成就管线
- D6: DomainEventBus 事件发布补全 + 解锁 Overlay + 成就同步
- 预估：1 周

### Phase 4：小组件与快捷操作
- D8: Widget 完成操作 + deep-link + 数据变更刷新
- D14: 通知栏快速添加 + Widget 快速添加 + 模板快速创建
- 预估：2 周

### Phase 5：智能输入与新视图
- D9: SmartDateParser + QuickCaptureFab 集成
- D10: 看板视图
- 预估：2 周

### Phase 6：专注与习惯增强
- D11: FocusDndService + 专注标签 + 白噪音分类
- D12: 灵活频次 + 习惯分组 + 模板扩展
- 预估：2 周

### Phase 7：深度集成与共享
- D7: 倒数日/纪念日 alarm + 课程 deep-link
- D5: 共享空间 API 验证 + 邀请流程 + 标志 + viewer 执行
- 预估：2 周

### Phase 8：数据可视化
- D13: ReportEngine + 统计页扩展 + 跨模块分析
- 预估：2 周

### Phase 9：国际化
- D15: ARB 提取 + AppLocalizations + BrandStrings 对接 + 逐页替换
- 预估：3 周（可与其他 phase 并行）

---

## 附录 A：FeatureFlags 扩展

```dart
// 新增开关
static const bool _kSmartDateParserDefault = false;
static const bool _kKanbanViewDefault = false;
static const bool _kFocusDndDefault = false;
static const bool _kFlexibleHabitDefault = false;
static const bool _kI18nDefault = false;

static bool get smartDateParser => _smartDateParserOverride ?? _kSmartDateParserDefault;
static bool get kanbanView => _kanbanViewOverride ?? _kKanbanViewDefault;
static bool get focusDnd => _focusDndOverride ?? _kFocusDndDefault;
static bool get flexibleHabit => _flexibleHabitOverride ?? _kFlexibleHabitDefault;
static bool get i18n => _i18nOverride ?? _kI18nDefault;
```

所有新特性默认关闭，灰度验证后逐步翻开。

## 附录 B：DomainEventType 扩展

```dart
enum DomainEventType {
  // 现有
  todoCreated,
  todoCompleted,
  habitCreated,
  habitCheckedIn,
  pomodoroCompleted,
  goalCreated,
  goalAchieved,
  goalMilestoneCompleted,
  diaryWritten,
  themeSwitched,
  // 新增
  todoDeleted,
  habitDeleted,
  goalDeleted,
  timeEntryCreated,
  achievementUnlocked,
  workspaceJoined,
  workspaceLeft,
  countdownReached,
  anniversaryReached,
}
```

## 附录 C：Deep-link URI Scheme 完整列表

```
duoyi://todo/{id}                 打开待办详情
duoyi://todo/{id}?confirm=1       弹出完成确认（闹钟场景）
duoyi://habit/{id}                打开习惯详情
duoyi://habit/{id}?confirm=1      弹出打卡确认
duoyi://goal/{id}                 打开目标详情
duoyi://countdown/{id}            打开倒数日
duoyi://anniversary/{id}          打开纪念日
duoyi://course/{id}               打开课程详情
duoyi://calendar?date=2026-05-15  打开日历并选中日期
duoyi://focus                     进入专注页
duoyi://time-audit                进入时间足迹
duoyi://achievements              进入成就页
duoyi://quick-todo                弹出快速待办对话框
duoyi://quick-focus               直接开始专注
```
