# 小组件三项交互设备验收

本页记录本轮三项交互在 Android API 35 ARM64 Pixel 5 模拟器上的实际 Launcher 验收。证据对应分支 `fix/android-input-settings-device-test`、版本 `1.1.54+140020`，最终 Debug APK SHA256 为 `84eeb8b3cfab751ec7f9171d70553a6398685343a267e73c62b0652a943bd3d5`。

## 设备边界

- 设备：`emulator-5554` / `duoyi_api35_arm64` / API 35 / 1080×2340 / density 2.75。
- Launcher：Pixel Launcher 前台；组件根 bounds 为 `[64,466,767,1032]`（703×566 px）。
- 物理实例：ID2 `DuoyiTodoWidgetProvider`，ID3 `DuoyiFocusHabitDetailedWidgetProvider`；覆盖安装后仍保留。
- 最终安装包的 `base.apk` SHA 与本地 APK 完全一致；未清除应用数据、未升版本、未提交或发布。

## 验收结果

### 1. 日历月份滑动

- 当前月 `2026-10` 显示完整 31 天，每个日期一次，weekday 列正确。
- 单次向上滑动后出现 `2026-11`。
- 普通只读 refresh 后仍停留在 11 月；点击 Today 后返回 10 月。
- 证据：[`calendar-current-final.png`](calendar-current-final.png)、[`calendar-other-month-final.png`](calendar-other-month-final.png)、[`calendar-refresh-kept-final.png`](calendar-refresh-kept-final.png)、[`calendar-today-final.png`](calendar-today-final.png)。机器断言见 `verification.json` 的 `calendar`。

### 2. 专注直接控制

最终包上按“单次输入后独立观察”完成一条干净链路：

1. Start：一次点击后为 `running`、session `focus-1793091903385472`、revision 1、running snapshot 存在、完成记录 0；见 [`clean-running.png`](clean-running.png)。
2. Pause：一次截图确认坐标点击后为 `paused`、同 session、revision 2、剩余 1448 秒、running snapshot 消失；见 [`clean-paused.png`](clean-paused.png)。
3. 暂停 UI：新鲜 AX 树确认首按钮文案为“继续”，停止按钮可用，四标签可见且无 ANR；报告内容保存在 scratch 的 `clean-paused-buttons.json`，摘要在 `verification.json`。
4. Resume：一次点击后通过直接读取 `FlutterSharedPreferences` 观察到同 session、revision 3、state `running`、running snapshot 存在。此次截图命令超时，因此不把 Resume 伪装成截图证据；它作为持久化状态证据记录。
5. Stop：一次点击后为 idle、新 session `focus-1793092344693795`、无 running snapshot、完成记录仍为 0；见 [`clean-stopped.png`](clean-stopped.png)。

按钮前置截图：[`clean-before-pause.png`](clean-before-pause.png)。旧的 `focus-running-final.png` 观察到的实际状态是 idle，已明确排除，不作为通过证据。

### 3. 待办上下滚动与四象限排序

- 独立 fixture 共 12 条，Q1/Q3/Q2/Q4 各 3 条；组件计数显示 12。
- 首屏显示 Q1（重要且紧急）；向上连续滑动后可看到 Q3/Q2，末尾显示 Q4（不重要且不紧急）。
- 顶部和末尾均保持四标签与 Launcher 前台，无 ANR。
- 证据：[`todo-populated-top.png`](todo-populated-top.png)、[`todo-populated-bottom.png`](todo-populated-bottom.png)。清理后计数回到 0 的截图为 [`todo-cleaned-empty.png`](todo-cleaned-empty.png)。

## 自动化与构建

- 修复后的资源静态测试：`flutter test test/services/android_widget_resources_test.dart` → **41 passed / 0 failed / 0 skipped**；新增断言覆盖 `HomeWidgetBackgroundService` 的 `exported=true + BIND_JOB_SERVICE`。
- 修复后的 Debug APK：`flutter build apk --debug` → **成功**；241,078,125 bytes；SHA 如上。
- 前置完整 Dart 门禁：174 个真实用例、`dart analyze --fatal-infos`、格式与 diff 检查通过；Native 月历 JVM 16/16 通过。上述两项来自本轮单点 Manifest 修复之前，Manifest 修复后重新执行了资源测试与 APK 构建。

## 清理与排除项

- fixture 清理：12 个本轮自有待办已删除，`after_todo_count=0`；清理前后均为 signed-out，未触碰用户数据。
- 专注最终状态为 idle，完成记录 0。
- 设备上旧 Job 的 04:34:39 绑定超时只作为排查历史；修改 `HomeWidgetBackgroundService` 为系统可绑定的 `exported=true` 后，最新动作记录为 `START → STOP last work dequeued`，最终 Start/Pause/Resume/Stop 均由最终包完成。
- 未覆盖：签名发布 APK、真机、其他 Launcher/ROM、iOS、Web 组件真实登录预览；Web 服务器仅保持运行，不能把登录页当作组件 E2E。
