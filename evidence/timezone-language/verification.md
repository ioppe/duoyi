# 语言与应用时区验证记录

## 需求

- 界面语言默认跟随系统，用户可以显式设置简体中文 / English，切换立即生效并持久化。
- 应用时区默认跟随系统，用户可以固定 IANA 时区；“今天”、今日页、日历、按天统计、习惯周期、提醒等全局日期随之改变，而同步时间戳、`updatedAt`、计时已流逝时长仍是真实瞬时。

## 实现要点

| 关注点 | 位置 |
| --- | --- |
| 应用壁钟 | `lib/core/app_clock.dart`（`now/date/dateOnly/today/watch/notifyDayChanged/changes`） |
| 时区解析与切换 | `lib/core/local_timezone_resolver.dart`（`timezoneListenable`、`setApplicationTimeZone`、`refresh`） |
| 时区偏好持久化与提醒重放 | `lib/providers/preferences_provider.dart`（`setAppTimeZone`、`refreshResolvedTimeZone`） |
| 跟随系统语言 + 显式覆盖 | `lib/core/i18n.dart` 中的 `LocaleProvider`、`lib/widgets/language_settings_tile.dart` |
| 设置入口 | “我的 → 个性设置 → 日期与日历”；“扩展 → 语言” |
| 启动装配与跨日/回前台重新解析 | `lib/main.dart`（`AppClockScope`、日期翻转监听、恢复前台重放提醒） |

存储键：`duoyi_locale_v1`（`system` / `zh` / `en`）、`pref_app_timezone_mode`（`system` / `fixed`）、`pref_app_timezone_iana`。

## 语义边界

- 按所选时区计算：今日页与日历的“今天”、日期分组、按天统计、习惯打卡周期、提醒触发时刻、黄历与日期格式化。
- 保持真实瞬时：同步时间戳、`updatedAt`、token 过期时间、计时器已流逝时长、番茄钟会话起点。
- 浮动日期（待办 `date`、纪念日等只存年/月/日的数据）不因换时区平移。
- `SmartTodoDraft.date` 保留时分（`ai_service._fallbackScheduleDraft` 用 `startAt = draft.date`）；日期归一化只作用于持久化的 `TodoItem.date` 一类的浮动字段。

## 自动化验证

- `flutter analyze --no-pub`：`No issues found!`
- 完整套件（`TZ=UTC flutter test --no-pub`）：**1713 通过 / 1 失败**，末尾计数与失败项见 `full-tests.txt`。唯一失败是既有基线 `test/screens/todo_batch_static_test.dart:122`：断言要求 `_TodoViewMode.list =>\n` 后跟 28 空格缩进的 `NotificationListener<ScrollNotification>`，而 `lib/screens/todo_screen.dart` 中该行是 12 空格；该文件与 HEAD 逐字节一致，属重构前既有失败。
- 静态守卫套件（`test/**/*_static_test.dart`）：**333 通过 / 1 失败**（同一基线），见 `static-guard-tests.txt`。
- 时区与时区相关专项：`application_timezone_services`、`app_clock_test`、`locale_preferences_test`、`local_timezone_resolver_test`、`preferences_provider_test`、`localization_timezone_settings_test`、`timezone_wallclock_pbt_test` 全部通过。
- 静态守卫是按等价新实现重定向的，没有删除断言：
  - `calendar_multiday_static_test` → `DateTime(y, m, d + 1)` / `DateTime(y, m, d - 1)` 的 DST 安全写法。
  - `pomodoro_provider_test` → `_lastDate = _todayKey();`。
  - `anniversary_remind_forward_test` → `!remindAt.isAfter(AppClock.now())`。
  - `habit_grouping_static_test` / `today_mine_static_test` / `calendar_local_event_static_test` / `calendar_day_timeline_static_test` → 改为 `AppClock.now()` / `AppClock.date(...)`。
  - `diary_mood_stats_dark_test` → 先压缩空白再匹配 `surfaceContainerHighest .withValues`。

## 真实浏览器验证

用 `flutter build web --release --no-pub` 产物在本地预览（`http://127.0.0.1:18655/`），以 `agent-browser` 操作真实界面：

1. 系统语言 `en-US`、本地无显式选择时，界面为英文 —— 默认跟随系统生效。
2. 通过“个性设置 → 日期与日历 → 界面语言”改为简体中文，界面**无需刷新即刻**变为中文，见 `../screenshots/timezone-language/language-zh-settings.png`。
3. 将应用时区改为 `Asia/Tokyo`，设置项副标题显示 `Asia/Tokyo` 与新时区当前时间。
4. 同一时刻纽约仍是 10 月 18 日，而今日页与万年历显示 `10月19日 · 周一`，证明全局日期跟随应用时区，见 `../screenshots/timezone-language/today-asia-tokyo.png`。

验证结束后已清除浏览器本地 `flutter.duoyi_locale_v1`、`flutter.pref_app_timezone_mode`、`flutter.pref_app_timezone_iana`，恢复为“跟随系统 + 系统时区”。

## 已知限制

- Flutter Web 语义层会把设置项整行合并成一个 `flt-tappable` 节点，行尾下拉菜单无法用指针直接点开（既有下拉菜单同样如此）。键盘聚焦该节点后按 Enter 可正常选择，但屏幕阅读器用户的操作路径不理想。
- 主机为一个 DST 有歧义的时区时，`almanac_screen_test.dart` 有两项失败；在使用 `TZ=UTC` 的测试环境（与 CI 一致）下通过。

本次未提交、推送或部署到生产站点，生产实例 `https://todo.skydrow.site` 未受影响。
