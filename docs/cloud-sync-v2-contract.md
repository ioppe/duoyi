# CloudSync v2 契约（Task 23 / Requirements 12）

对齐 `.kiro/specs/app-alignment-overhaul/design.md §2.6`：客户端走 Offline-First，本地写入 → Provider 持久化 → CloudSync 排队 → ApiClient push。

## 特性开关

`lib/core/feature_flags.dart` 中 `FeatureFlags.cloudSyncV2` 当前默认 `true`，测试可显式覆盖。
- 关闭：业务记录只落本地 `SharedPreferences`，不发出个人数据同步请求；公开功能配置仍可独立刷新。
- 开启：已登录账号按下述契约同步；管理员的 `backup_enabled` 仍有最终控制权，手动操作不能绕过。

## 后端配置与同步触发时机

- 每次应用冷启动在首帧后立即刷新 `/api/config`，不再等待约 75 秒的后台闲时队列。已保存登录且开启自动同步时，配置就绪后主动同步个人数据，不再固定等待约 120 秒。
- 登录或切换账号后启动同步；本地改动沿用既有节流队列，远端 SSE/版本探针继续按修订变化拉取。回到前台时刷新配置并在符合条件时同步。
- 用户点击我的页的「云同步」卡片会主动刷新服务器配置并执行一次数据同步；手动刷新绕过配置的 30 秒成功缓存，但复用并升级在途的后台请求，不叠加第二个配置请求。自动同步关闭时仍可手动执行一次；管理员关闭云端备份时不能强制上传。
- `BackendSyncCoordinator` 统一配置刷新、身份校验和业务同步，UI 经 `SyncStatusController` 请求操作，不直接调用底层同步 Provider。同步中禁止重复点击；失败保留可诊断状态并可再次点击。
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

## 用户偏好（`preferences`）与设备配置

`preferences` 使用 `{updatedAt, values, changedKeys?}` 载荷，服务端保留既有键级合并。设备日期、导航、时区和提醒等 `pref_*` 不再随账号清理删除；退出仍清除旧账号同步基线、待提交键和私有业务缓存，不把它们带入其他服务器/账号。

- 保存某项偏好时，在 setter 完成前等待值、更新时间戳、变更键集合和待同步标记全部持久化；并发保存不能互相覆盖变更键。
- 更新时间戳采用真实 UTC 瞬时；本地有效时间较新时，旧云快照不能仅因进程内没有 pending 键而回滚本地偏好。真正较新的云快照继续按既有规则应用。
- 读取偏好会等待在途保存；若读取期间又发生用户修改，同一个读取 Future 自动重试合流，不能只保住修改字段而丢下无关设置不刷新。
- 悬浮窗尺寸等本机设置仍不加入云同步白名单；管理员全站 `settings` 与用户 `preferences` 是不同数据域。

完整存储与重部署边界见 [配置、登录会话与部署隔离](configuration-persistence.md)。

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
