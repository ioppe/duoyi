# CloudSync v2 契约（Task 23 / Requirements 12）

对齐 `.kiro/specs/app-alignment-overhaul/design.md §2.6`：客户端走 Offline-First，本地写入 → Provider 持久化 → CloudSync 排队 → ApiClient push。

## 特性开关

`lib/core/feature_flags.dart` 中 `FeatureFlags.cloudSyncV2` 当前默认 `true`，测试可显式覆盖。
- 关闭：业务记录只落本地 `SharedPreferences`，不发出个人数据同步请求；公开功能配置仍可独立刷新。
- 开启：已登录账号按下述契约同步；管理员的 `backup_enabled` 仍有最终控制权，手动操作不能绕过。

## 后端配置与同步触发时机

- 每次应用冷启动在首帧后立即刷新 `/api/config`，不再等待约 75 秒的后台闲时队列。已保存登录且开启自动同步时，配置就绪后主动同步个人数据，不再固定等待约 120 秒。
- 待办本地快照在首帧后独立水合，不等待其他模块的延迟补载或云端变更集；本地与云端内容相同也应直接在今日显示符合既有筛选规则的任务。初始读取全程抑制脏标记，重复入口复用已有水合；同步触发集合变更回调而待办仍未水合时补读本地存储，实际 `todos` 变化仍强制重读。普通读取与强制重读共用存储串行队列，损坏数据修复写入前核对原始快照，避免覆盖读取期间收到的云端结果。存储被连续替换达到重试上限时，本次水合及等待它的写入失败，不写回旧快照，后续读取可重试。账号代际、三方合并和任务日期不因初始化修复改变。
- 登录或切换账号后启动同步；本地改动沿用既有节流队列，远端 SSE/版本探针继续按修订变化拉取。回到前台时刷新配置并在符合条件时同步。
- 用户点击我的页的「云同步」卡片，或在 Android 原生端的内容页顶部下拉，会主动刷新服务器配置并执行一次数据同步；下拉显示转圈，直到同步结果落盘且相关页面 Provider 回载完成。空白内容、不足一屏的列表和横向标签内的纵向列表也可下拉；横向滑动和列表中部的普通滚动不触发同步。Web 与桌面端保留原交互。
- 手动刷新绕过配置的 30 秒成功缓存，复用并升级在途的后台配置请求；业务同步已在运行时等待其结束再执行本次主动请求，重复手动请求共享同一个 Future。本地有改动时沿用上传与三方合并，无改动时仍调用 `/api/sync/pull` 按集合 hash 拉取远端变化，不等待轮询。自动同步关闭时仍可手动执行一次，不改变开关；管理员关闭云端备份或同步特性关闭时不能强制请求个人数据。
- `BackendSyncCoordinator` 统一配置刷新、身份校验和业务同步，UI 经 `SyncStatusController` 请求操作，不直接调用底层同步 Provider。卡片同步中禁止重复点击；下拉失败时给出可重试提示，保留本地数据和待同步标记。等待期间切换账号、服务器或退出时，旧请求不能对新身份执行或回写。
- 卡片中的上次成功同步仍保存为真实时间点，显示时按 `AppClock` 的应用时区转换；时区切换只刷新此处文字，不改同步基线或发起卡片同步请求。
- `/api/config` 是公开功能配置，不是 AI 模型调用，也不是用户数据备份。访客只拉公开配置；个人数据请求必须有当前登录身份。配置与同步结果均遵守服务器/账号代际隔离。
- AI 配置明确区分未知、加载中、成功和失败。「时光足迹」进入时按 30 秒缓存刷新，失败可原地重试；只有配置成功且 `ai_enabled=false` 时才提示管理员开启，未知或断网不能显示为管理员关闭。

## Goal 请求体（POST /api/v1/goals）

```jsonc
{
  "id": "<uuid v4>",
  "title": "string",
  "category": "recommend|health|study|sport|emotion|custom",
  "icon": "string",                        // MaterialIcons name
  "colorValue": 4294952960,
  "recurrence": {
    "frequency": "none|daily|weekly|monthly|yearly",
    "interval": 1,
    "byWeekdays": [0, 2, 4],               // 0=周一
    "byMonthDay": null,
    "endDate": null,                       // ISO local; 服务端存 UTC
    "maxOccurrences": null
  },
  "scheduling": {
    "mode": "fixed|random",
    "fixedWeekdays": [0, 2, 4],
    "fixedMonthDays": null,
    "randomMinGapDays": null,
    "randomMaxPerWeek": null,
    "randomMaxPerMonth": null
  },
  "skipHolidays": true,
  "focus": {
    "enabled": true,
    "presetId": "pomodoro-25",
    "focusSeconds": 1500,
    "whiteNoise": "rain"
  },
  "reminder": {
    "enabled": true,
    "kind": "push|alarm",
    "hour": 20,
    "minute": 0,
    "daysBefore": 0,
    "vibrate": true,
    "fullScreen": true
  },
  "timeTargetSeconds": 1800,
  "dailyTargetCount": 1,
  "tz": "Asia/Shanghai",                   // IANA 名
  "updatedAt": "2025-01-15T10:30:00+08:00"  // 本地 ISO with offset
}
```

## Todo 请求体（POST /api/v1/todos）

追加字段（相对旧版）：`reminder / focusLink / timeTargetSeconds / postponeHistory / autoToggleByChildren / isArchivedAfterRollover`。schema 与 `lib/models/todo.dart.toJson()` 的输出 1:1。

## 自定义清单（`list_groups`） / POST /api/sync

清单类型不再固定为六个内置模板：用户可在新建表单里新增、重命名、删除清单。集合走统一的 `/api/sync` 整包合并，`API_CONTRACT_VERSION` 随之为 `2026-06-01.6`，`API_CONTRACT_FEATURES.list_groups = true`。

```jsonc
"list_groups": [
  {
    "id": "8f1c…",                 // 客户端生成的 uuid
    "name": "旅行",                 // 去空白、1–24 字符、同账号内归一化后唯一
    "sortOrder": 6,                // 递增整数，决定自定义清单展示顺序
    "workspaceId": "private",      // 与 TodoItem.workspaceId 同一套空间语义
    "isDeleted": false,            // 墓碑：服务端保留，客户端隐藏
    "createdAt": "2026-06-02T10:00:00.000",
    "updatedAt": "2026-06-02T10:00:00.000"
  }
]
```

- 合并：按 `id` 取并集，逐条 `updatedAt` 较新者胜；`isDeleted` 与普通修改同权，旧时间戳不能复活墓碑。
- 隔离：每个账号独立存储；`/api/sync/pull` 只返回本账号数据。
- 备份：服务端备份直接快照 SQLite，`sync_data.list_groups` 随库一起进出；管理员清空用户数据时会一并重置。
- 客户端：`ListGroupProvider` 负责本地持久化与校验，`CloudSyncProvider` 将其纳入集合/条目哈希与增量上传；清单名同时参与新建表单的收纳选择器与 AI 拆解白名单（内置模板 ∪ 自定义清单 ∪ 已有任务清单名，按写权限过滤）。选择器交互见 [清单类型收纳选择器](list-group-picker.md)。

## 账号偏好（`preferences`） / POST /api/sync

现有同步接口的 `preferences` 对象携带 `updatedAt`、`values` 及本次显式修改的 `changedKeys`。界面语言键 `duoyi_locale_v1` 加入客户端字符串白名单，值为 `zh`、`en` 或 `system`；语言与日期、时区、导航等已支持偏好复用同一合并链路，无需新增服务端接口。

- 用户选择先落本地，再等待偏好时间戳、变更键和待同步标记持久化；纯加载、云端回写及系统语言变化不新增变更键。
- 新端登录后使用现有账号同步拉取偏好，`preferences` 发生变更时同时重新加载普通偏好和语言 Provider，界面即时采用云端选择。
- `system` 表示每端跟随各自系统，不能上传解析后的系统语言代替该值；首次启动未作选择时不持久化语言覆盖值。
- 沿用按变更键合并和真实瞬时时间戳，旧服务端快照缺少语言键时保留本地既有语言选择，其他设备只修改提醒等独立偏好时不覆盖语言。
- 应用锁、凭证、权限授权和其它未列入白名单的设备配置仍遵循各自本地存储边界。

## 用户偏好（`preferences`）与设备配置

`preferences` 使用 `{updatedAt, values, changedKeys?}` 载荷，服务端保留既有键级合并。设备日期、导航、时区和提醒等 `pref_*` 不再随账号清理删除；退出仍清除旧账号同步基线、待提交键和私有业务缓存，不把它们带入其他服务器/账号。

- 保存某项偏好时，在 setter 完成前等待值、更新时间戳、变更键集合和待同步标记全部持久化；并发保存不能互相覆盖变更键。
- 更新时间戳采用真实 UTC 瞬时；本地有效时间较新时，旧云快照不能仅因进程内没有 pending 键而回滚本地偏好。真正较新的云快照继续按既有规则应用。
- 读取偏好会等待在途保存；若读取期间又发生用户修改，同一个读取 Future 自动重试合流，不能只保住修改字段而丢下无关设置不刷新。
- 悬浮窗尺寸等本机设置仍不加入云同步白名单；管理员全站 `settings` 与用户 `preferences` 是不同数据域。

完整存储与重部署边界见 [配置、登录会话与部署隔离](configuration-persistence.md)。

## 当前共享专注与历史同步

同账号实时专注走独立的运行态接口及 WebSocket，协议见 [同账号多端专注同步](focus-runtime-sync.md)。`pomodoro_sessions`、`focus_penalties` 和 `time_entries` 继续走现有历史同步；运行态不放入 `pomodoro_config`、偏好或房间排行榜 presence，也不参与普通 `updatedAt` 三方合并。服务端结算与云同步写入使用同一数据库事务边界，避免并发整行替换覆盖历史。客户端历史/配置重载不能以旧本地运行快照覆盖已接管的共享会话。

访客和明确不支持实时专注的旧后端保留本地计时；已支持的后端暂时离线时保留共享会话投影并等待重连，不创建第二条独立本地会话。多条普通登录可同时有效，退出一端不撤销其它端凭据。

## 时间规范

- 请求体的所有 `DateTime` 字段使用 **客户端本地 ISO** 并附 `tz`；
- 服务端只存 **UTC + tz 名** 两列；
- 响应时返回 UTC，客户端用 `LocalTimezoneResolver.currentIana` 转回本地展示。

## 离线队列与重试

- 断网写入先持久化到 `SharedPreferences` 下的 `cloud_sync_queue`；
- 联网后按 `exponential backoff` 重放：`base=1s, factor=2, maxAttempts=5`；
- 每次尝试后持久化"最后状态"（`pending / syncing / failed / synced`）；
- UI 侧在有 `pending` 时显示红点角标（建议挂在 `MineScreen` 头像或侧栏）。

## 早期任务索引（Task 23 历史拆分）

| 子任务 | 文件 | 说明 |
|--------|------|------|
| 23.2 | `lib/services/cloud_sync_provider.dart` / `lib/services/api_client.dart` | 调用点判读 `FeatureFlags.cloudSyncV2`；请求体按本文档 schema 构造；队列 + 指数退避。 |
| 23.3 | `backend/main.py` | 已验证：当前存储为 opaque JSON TEXT + `_merge_by_timestamp` on list items，新 Goal/Todo 字段自动直通，无需服务端 schema 变更。未来若要按字段级索引查询（如"按 kind=alarm 过滤"），再单独加列。 |
| 23.4 | `lib/screens/mine_screen.dart` / `lib/widgets/...` | "有未同步改动"角标（命中 cloud sync 队列非空时显示）。 |

> 上表保留早期任务拆分供追溯；当前客户端已通过 `lib/providers/cloud_sync_provider.dart` 与 `/api/sync/*` 实现同步，触发时机以前文为准。关闭 `cloudSyncV2` 仅停止个人数据同步，不阻止公开配置刷新，本地内容继续可用。
