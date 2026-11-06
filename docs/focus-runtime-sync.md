# 同账号多端专注同步

同一服务器、同一账号共享一个当前专注阶段。服务端决定状态和结算；Flutter Provider、Android 通知/小组件和 macOS 悬浮窗只是状态投影和控制入口。访客及未声明能力的旧后端保留本地专注。

## 协议

能力：`GET /api/config` 的 `features.focus_runtime_sync = true`。

后端运行环境需安装 `backend/requirements.txt` 中的 WebSocket 实现（`websockets==15.0.1`）；仅安装基础 `uvicorn` 不会提供 WebSocket 协议处理器。部署后应使用真实 TCP WS 握手核验，HTTP 正常或 TestClient 的 WS 用例通过不足以证明运行环境具备该能力。

- `GET /api/focus/runtime`：当前快照，读取前补处理到期阶段。
- `POST /api/focus/runtime/commands`：提交控制命令，成功返回快照。
- `WS /ws/focus/runtime/events`：认证成功后立即发快照，状态改变后向同账号全部连接推送；事件为 `{"event":"focus.runtime","data": <快照>}`。客户端可发送 `{"event":"ping"}` 校准/补拉；服务端定时核对数据库版本，兼容多个 worker，重新校验身份。

命令：`{commandId, deviceId, sessionId, expectedRevision, action, payload?}`。`commandId` 为客户端 UUID，`sessionId` 和 `expectedRevision` 必须匹配当前阶段；身份从认证取得，不采信载荷中的用户 ID。同一个命令 ID 不能换载荷。冲突用 HTTP 409 返回，客户端重新读取权威快照，不盲目重放旧操作。

快照：

```json
{
  "serverNowMs": 0,
  "runtime": {
    "sessionId": "server-uuid",
    "revision": 0,
    "status": "idle",
    "mode": "countdown",
    "phase": "focus",
    "durationMs": 1500000,
    "elapsedMs": 0,
    "anchorAtMs": null,
    "startedAtMs": null,
    "completedSessions": 0,
    "sourceDeviceId": "",
    "config": {},
    "taskName": null,
    "todoId": null,
    "subtaskId": null,
    "todoTitle": null,
    "tag": null,
    "focusRoomId": null
  },
  "lastSession": null,
  "lastPenalty": null,
  "syncVersion": 0
}
```

`lastSession` 是最近一次结算且仍存在于历史中的 `PomodoroSession.toJson()` 记录；`lastPenalty` 是最近一次服务端控制处罚的 `PomodoroFocusPenalty.toJson()` 记录。它们供即时幂等回填，完整历史仍由 CloudSync 同步。删除历史后不得凭结算凭证复活记录。

`revision` 在用户运行态中单调递增，回到 idle 不归零。每次进入新阶段更换 sessionId，暂停/继续保留。`sourceDeviceId` 保持本阶段发起设备，不能被暂停等操作覆盖；设备本地严格模式监控只在发起设备执行，远端状态应用不重复写控制处罚。

## 状态与操作

- `start`：只接受 idle；payload 含 `mode`、`config` 和任务字段，可选 `phase`（focus/shortBreak/longBreak，缺省沿用当前阶段），让空闲时长/模式选择在开始时一并提交。正计时仅接受 focus。配置沿用 PomodoroConfig 的秒数/自动轮转字段；声音音量及原生权限不由会话覆盖。idle 选择作为本机启动草稿，不改写服务端会话或控件绑定；确认开始后所有设备投影同一阶段。
- `pause` / `resume`：running → paused / paused → running。冻结/续接累计毫秒，暂停间隔不计入。
- `stop` / `reset`：回到 focus idle，倒计时满时长或正计时零，不写完成记录，清周期计数并更换身份。
- `finish`：主动完成 focus；倒计时沿用主线的目标时长结算语义，正计时按累计有效时长结算（沿用上限）。
- `skip`：沿用主线 focus → shortBreak、break → focus，进入 idle，不写完成记录。
- `update`：当前任务/标签/房间元数据的显式更新。只更新白名单字段并校验版本，不能借此修改状态/计时/发起设备。
- 自然倒计时到期：服务端一次结算并按本场配置进入休息/下一次 focus；自动开始的阶段以理论到期时刻为锚点。后台补处理有界批次，保留后续到期工作，不能静默制造无限循环。

运行中显示的累计时长为 `elapsedMs + (serverNow - anchorAtMs)`；倒计时剩余为 `max(0, durationMs - 累计)`。客户端校准服务器时钟后用单调时钟推进，重连/恢复时再校准。同步模式的本地 tick 和原生通知到期不调用本地完成结算。

## 存储、幂等和历史

新增独立 `focus_runtime`、`focus_commands`、`focus_settlements` 表，不把运行态塞入普通配置或排行榜 presence。会话状态改变、命令凭证、唯一结算、历史更新在一个 SQLite 短事务中提交；事务结束后发送网络消息。命令凭证唯一键为 `(user_id, command_id)`，结算唯一键为 `(user_id, session_id)`。数据库约束和条件更新负责并发正确性。

完成历史保持现有 `sync_data.pomodoro_sessions` JSON 形状，以共享 sessionId 为记录 id。时间足迹保持现有 shape 和 `pomodoro:<sessionId>` 去重键，并沿用主线的历史时间口径。控制处罚一次命令只记一条；普通远端应用不发布重复完成领域事件。所有修改 sync_data 的路径（包括既有 push/delta 和服务端结算）必须从读取前开始共享事务保护，避免读旧整行后替换丢失记录。
账号保留的备份清理会清空任务、配置和运行状态，并推进 revision、生成新的 idle 阶段，避免在线客户端因版本回到 0 而永久拒绝快照；账号删除则级联移除运行态、命令凭证与结算凭证。

## 客户端与平台

`FocusSyncCoordinator` 在应用根级绑定 AuthProvider / PomodoroProvider，离开专注页不停止连接。按服务器、用户、凭证代际丢弃旧响应；换号先断连接、清在途命令和设备效果，不发送账号级 stop。登录新后端后先拉权威快照，再允许控制。新后端暂时离线时不得退回独立本地会话；旧后端仅在明确无此能力/路由时使用本地模式。

CloudSync 重载专注历史和配置时不能恢复旧的本地运行态覆盖远端会话。同步状态以计时卡片头部阶段标题右侧的白色云图标表示，不在计时控件上方常驻状态文字。已登录、支持共享运行态、已取得权威快照且实时连接正常、没有未确认错误时使用同步云图标，点击提示“多端专注已同步”；其余使用未同步云图标，未登录点击提示“登录后同步多端专注”，已登录点击提示“离线未同步”。提示走 I18n，图标保留可访问标签与点击区域。控制错误不能成为未处理 Future。设备 ID 是无凭证的设备本地偏好，普通账号清理时保留。

macOS 收到新 running 会话时，在应用可用的条件下打开一次悬浮窗；之后只 update。关闭只隐藏本机，同一场后续消息不重弹；新一场再自动显示。保留应用锁、强制更新、账号/服务器变更和迟到 show 失效守卫。尺寸、位置、主题仍是设备本地属性。

在线进程保证实时同步；应用退出、系统挂起或网络断开时依靠恢复后的快照收敛。断网显示最后确认状态及连接状态，不自动重放过期的暂停/重置。Web 沿用同源，WebSocket URL 必须正确处理部署路径前缀和凭证脱敏。

## 验证范围

后端定向覆盖：状态转换、倒/正计时、暂停、自动轮转、双端竞争、命令重试/载荷冲突、唯一结算、云同步并发、用户隔离、撤销鉴权、两个同账号 WS 收到更新、旧客户端兼容。

Flutter 定向覆盖：快照投影及锚点补偿、乱序忽略、重复历史/处罚去重、换号迟到响应、断线/恢复、远端控制入口、同步重载不复活本地快照、悬浮窗自动显示/关闭不重弹、旧后端本地模式。真实 Android/macOS 跨设备 E2E 与完整发布构建独立记录，不能用单元测试代替。

## 多设备普通登录

共享专注依赖同账号各端同时拥有有效身份。`login_sessions` 从旧 `user_id` 主键迁移为 `token_hash` 主键，保留已有摘要、创建/到期/使用时间，不延长旧有效期。多个密码/邮箱登录并存，新登录不撤销其它设备；普通退出只删除请求携带的令牌。密码修改/重置、禁用/删除和管理员强制重登继续撤销该账号全部相关凭据。迁移在启动写事务内完成并保持幂等，见 [配置、登录会话与部署隔离](configuration-persistence.md)。
