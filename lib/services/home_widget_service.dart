import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_clock.dart';
import '../core/brand_strings.dart';
import '../core/home_widget_calendar.dart';
import '../core/home_widget_todos.dart';
import '../core/i18n.dart';
import '../core/iterable_extensions.dart';
import '../core/local_timezone_resolver.dart';
import '../core/platform_info.dart';
import '../core/smart_todo_draft.dart';
import '../models/habit.dart' show HabitKind;
import '../models/pomodoro.dart'
    show PomodoroType, PomodoroWidgetControlAction, PomodoroWidgetTimerState;
import '../providers/cloud_sync_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import 'android_widget_manager.dart';
import 'home_widget_action.dart';
import 'home_widget_action_bridge.dart';

/// 桌面动作执行时使用的一组业务 Provider。
///
/// 主 isolate 传入存活的实例；冷后台传入按 prefs 重新加载的实例。
class HomeWidgetLiveProviders {
  final TodoProvider todos;
  final HabitProvider habits;
  final PomodoroProvider pomodoro;

  const HomeWidgetLiveProviders({
    required this.todos,
    required this.habits,
    required this.pomodoro,
  });
}

/// Pushes today's stats and brand strings out to Android/iOS home widgets.
/// 在 web / 其他平台下为空实现。
class HomeWidgetService {
  static const String _androidTodoProviderName = 'DuoyiTodoWidgetProvider';
  static const String _androidFocusProviderName =
      'DuoyiFocusHabitWidgetProvider';
  static const String _androidHabitProviderName = 'DuoyiHabitWidgetProvider';
  static const String _androidCalendarProviderName =
      'DuoyiCalendarWidgetProvider';
  static const String _androidScheduleProviderName =
      'DuoyiScheduleWidgetProvider';
  static const String _androidGoalProviderName = 'DuoyiGoalWidgetProvider';
  static const String _androidCourseProviderName = 'DuoyiCourseWidgetProvider';
  static const String _androidNoteProviderName = 'DuoyiNoteWidgetProvider';
  static const String _androidAnniversaryProviderName =
      'DuoyiAnniversaryWidgetProvider';
  static const String _iosTodoWidgetName = 'DuoyiTodoWidget';
  static const String _iosFocusWidgetName = 'DuoyiFocusWidget';
  static const String _iosHabitWidgetName = 'DuoyiHabitWidget';
  static const String _iosCalendarWidgetName = 'DuoyiCalendarWidget';
  static const String _iosScheduleWidgetName = 'DuoyiScheduleWidget';
  static const String _iosGoalWidgetName = 'DuoyiGoalWidget';
  static const String _iosCourseWidgetName = 'DuoyiCourseWidget';
  static const String _iosNoteWidgetName = 'DuoyiNoteWidget';
  static const String _iosAnniversaryWidgetName = 'DuoyiAnniversaryWidget';
  static const String _appGroupId = 'group.com.duoyi.duoyi';

  /// 账号清理（登出/切号）时写回小组件的兜底 payload。文案值经 I18n 取词：
  /// en 用户登出后小组件不应回退为中文占位；其余为与语言无关的默认数值。
  @visibleForTesting
  static Map<String, Object> get accountPayloadDefaults => <String, Object>{
    'todo_count': 0,
    'habit_percent': 0,
    'habit_highlight_1': '',
    'habit_highlight_1_id': '',
    'habit_highlight_2': '',
    'habit_highlight_2_id': '',
    'habit_highlight_3': '',
    'habit_highlight_3_id': '',
    'pomodoro_today': 0,
    'focus_minutes_today': 0,
    'brand_app_title': I18n.tr('mine.about.title'),
    'nav_todo': I18n.tr('nav.todo'),
    'nav_habit': I18n.tr('nav.habit'),
    'nav_calendar': I18n.tr('nav.calendar'),
    'nav_focus': I18n.tr('nav.focus'),
    'todo_top3_count': 0,
    'todo_top3_1': I18n.tr('widget.todo_top3_empty'),
    'todo_top3_1_id': '',
    'todo_top3_2': '',
    'todo_top3_2_id': '',
    'todo_top3_3': '',
    'todo_top3_3_id': '',
    // 全部今日可见未完成待办（已排序）；新 key 缺省时原生回退旧 Top3。
    'widget_todo_items_json': '[]',
    'goal_highlight_1': I18n.tr('widget.goal_empty'),
    'goal_highlight_1_id': '',
    'goal_highlight_2': '',
    'goal_highlight_2_id': '',
    'goal_highlight_3': I18n.tr('widget.goal_hint'),
    'goal_highlight_3_id': '',
    'anniversary_highlight_1': I18n.tr('widget.anniversary_empty'),
    'anniversary_highlight_1_id': '',
    'anniversary_highlight_2': '',
    'anniversary_highlight_2_id': '',
    'course_highlight_1': I18n.tr('widget.course_empty'),
    'course_highlight_1_id': '',
    'course_highlight_2': '',
    'course_highlight_2_id': '',
    'course_highlight_3': '',
    'course_highlight_3_id': '',
    'note_highlight_1': I18n.tr('widget.note_empty'),
    'note_highlight_1_id': '',
    'note_highlight_2': '',
    'note_highlight_2_id': '',
    'note_highlight_3': '',
    'note_highlight_3_id': '',
    'memorial_highlight_1': I18n.tr('widget.anniversary_empty'),
    'memorial_highlight_1_id': '',
    'memorial_highlight_2': '',
    'memorial_highlight_2_id': '',
    'memorial_highlight_3': '',
    'memorial_highlight_3_id': '',
    'diary_highlight_1': '',
    'diary_highlight_1_id': '',
    'diary_highlight_2': '',
    'diary_highlight_2_id': '',
    'diary_highlight_3': '',
    'diary_highlight_3_id': '',
    'today_event_summary': I18n.tr('widget.no_schedule_today'),
    'schedule_highlight_1': '· ${I18n.tr('widget.no_schedule_today')}',
    'schedule_highlight_1_id': '',
    'schedule_highlight_2': '· ${I18n.tr('widget.schedule_open_calendar')}',
    'schedule_highlight_2_id': '',
    'schedule_highlight_3': I18n.tr('widget.schedule_timezone_hint'),
    'schedule_highlight_3_id': '',
    'calendar_month_summary': I18n.tr('widget.calendar_month_summary'),
    'calendar_day_counts_json': '{}',
    'calendar_timezone': '',
    'calendar_weekdays_json': homeWidgetCalendarWeekdayLabelsJson(),
    'calendar_day_count_label': I18n.tr('widget.calendar_day_count_label'),
    'calendar_month_title': I18n.tr('widget.calendar_month_title'),
    // 小组件 UI 纯展示文案（native 按 widget_* key 读取）；空态 {tab} 用默认导航词。
    'widget_todo_empty_hint': _todoEmptyHint(I18n.tr('nav.todo')),
    'widget_todo_count_unit': I18n.tr('widget.todo_count_unit'),
    'widget_habit_today_label': I18n.tr('widget.habit_today_label'),
    'widget_focus_count_label': I18n.tr('widget.focus_count_label'),
    'widget_focus_minutes_label': I18n.tr('widget.focus_minutes_label'),
    'widget_focus_next_label': I18n.tr('widget.focus_next_label'),
    'widget_focus_remaining_label': I18n.tr('widget.focus_remaining_label'),
    'widget_focus_open_label': I18n.tr('widget.focus_open_label'),
    'widget_focus_running_label': I18n.tr('widget.focus_running_label'),
    'widget_today_label': I18n.tr('widget.today_label'),
    'widget_focus_start_label': I18n.tr('widget.focus_start_label'),
    'widget_focus_resume_label': I18n.tr('widget.focus_resume_label'),
    'widget_focus_pause_label': I18n.tr('widget.focus_pause_label'),
    'widget_focus_stop_label': I18n.tr('widget.focus_stop_label'),
    'widget_focus_paused_label': I18n.tr('widget.focus_paused_label'),
    // 专注控制元数据默认值：空身份 + idle + revision 0 + 非正计时。
    'focus_timer_state': PomodoroWidgetTimerState.idle.wireName,
    'focus_timer_session_id': '',
    'focus_timer_revision': 0,
    'focus_control_scope': '',
    'focus_timer_count_up': false,
    'focus_summary': I18n.tr('widget.focus_not_started'),
    'habit_summary': I18n.tr('widget.habit_pending'),
    'streak_summary':
        '${I18n.tr('widget.streak_record_prefix')}0'
        '${I18n.tr('widget.streak_suffix')}',
    'next_focus_label': '25${I18n.tr('widget.next_focus_suffix')}',
    'focus_timer_running': false,
    'focus_timer_remaining_seconds': 0,
    'focus_timer_total_seconds': 0,
    'focus_timer_ends_at_millis': 0,
    'focus_timer_label': I18n.tr('widget.focus_countdown'),
    'habit_quick_check_id': '',
    'habit_quick_check_label': I18n.tr('widget.habit_quick_check_hint'),
    'widget_theme_brand_id': 'defaultBrand',
    'widget_theme_card_skin_id': 'plain_card',
    'widget_theme_dark': false,
    'widget_theme_primary': '#FFFF6B6B',
    'widget_theme_background': '#FFFFFFFF',
    'widget_theme_surface': '#FFFFFFFF',
    'widget_theme_nav_background': '#FFFFF6F2',
    'widget_theme_border': '#22FF6B6B',
    'widget_theme_text': '#FF333333',
    'widget_theme_muted_text': '#FF666666',
    'widget_theme_on_primary': '#FFFFFFFF',
    'widget_theme_accent_start': '#FFFF6B6B',
    'widget_theme_accent_end': '#FFFFB088',
    'widget_theme_background_asset_key': '',
    'widget_theme_corner_radius_dp': 13,
    'widget_theme_control_radius_dp': 8,
    'widget_theme_border_width_dp': 0,
  };
  static String _lastThemeSignature = '';
  static String _lastPushSignature = '';
  static Future<bool>? _accountPayloadClearInFlight;
  static bool _interactivityRegistered = false;

  /// 测试用：按“支持小组件的移动端”执行后台动作，便于在宿主机覆盖 payload
  /// 重算与刷新顺序；生产环境仍由 [PlatformInfo] 决定。
  @visibleForTesting
  static bool debugForceSupported = false;

  /// 测试用：替换原生 `refreshAllWidgets` 并强制走 Android 刷新分支，宿主测试
  /// 没有真实桌面实例时也能覆盖“0 命中 / 失败 / 命中”三种刷新结果；生产环境
  /// 仍由 [PlatformInfo] 与 [AndroidWidgetManager] 决定。
  @visibleForTesting
  static Future<int?> Function()? debugRefreshAllWidgetsOverride;

  static bool get _supported {
    if (kIsWeb) return false;
    if (debugForceSupported) return true;
    return PlatformInfo.isAndroid || PlatformInfo.isIOS;
  }

  /// 主 isolate 是否需要注册后台动作转发端口（web/桌面端不注册）。
  static bool get supportsBackgroundActions => _supported;

  /// 后台动作刷新原生组件用的 Android 原生通道。
  static bool get _androidBackgroundSupported =>
      PlatformInfo.isAndroid || debugForceSupported;

  static Future<bool> init() async {
    if (!_supported) return true;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      await registerBackgroundActions();
      return true;
    } catch (e, st) {
      debugPrint('[HomeWidget] init failed: $e\n$st');
      return false;
    }
  }

  /// 注册桌面小组件后台动作回调（每进程只注册一次）。
  ///
  /// [homeWidgetBackgroundCallback] 运行在 `home_widget` 创建的独立
  /// FlutterEngine 里，不共享主 isolate 的 Provider/BuildContext。
  static Future<bool> registerBackgroundActions() async {
    if (!_supported) return true;
    if (_interactivityRegistered) return true;
    try {
      final registered = await HomeWidget.registerInteractivityCallback(
        homeWidgetBackgroundCallback,
      );
      _interactivityRegistered = registered != false;
      return _interactivityRegistered;
    } catch (e, st) {
      debugPrint('[HomeWidget] register background callback failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> setDisplayMode(String mode) async {
    if (!_supported) return true;
    try {
      await HomeWidget.saveWidgetData<String>('widget_display_mode', mode);
      return await _updateAllWidgets();
    } catch (e, st) {
      debugPrint('[HomeWidget] setDisplayMode($mode) failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> updateTheme(HomeWidgetThemePayload theme) async {
    if (!_supported) return true;
    await _drainPendingAccountClear();
    final signature = theme.signature;
    if (signature == _lastThemeSignature) return true;
    try {
      await Future.wait(theme.saveOperations());
      final ok = await _updateAllWidgets();
      if (ok) _lastThemeSignature = signature;
      return ok;
    } catch (e, st) {
      debugPrint('[HomeWidget] updateTheme failed: $e\n$st');
      return false;
    }
  }

  static void resetAccountCache() {
    _lastThemeSignature = '';
    _lastPushSignature = '';
    _accountPayloadClearInFlight =
        (_accountPayloadClearInFlight ?? Future<bool>.value(true)).then(
          (_) => clearAccountWidgetData(),
        );
  }

  static Future<bool> clearAccountWidgetData() async {
    if (!_supported) return true;
    try {
      final initialized = await init();
      if (!initialized) return false;
      await Future.wait(
        accountPayloadDefaults.entries.map(_saveWidgetPayloadEntry),
      );
      return await _updateAllWidgets();
    } catch (e, st) {
      debugPrint('[HomeWidget] clear account widget data failed: $e\n$st');
      return false;
    }
  }

  static Future<void> _drainPendingAccountClear() async {
    while (true) {
      final pending = _accountPayloadClearInFlight;
      if (pending == null) return;
      await pending;
      if (identical(_accountPayloadClearInFlight, pending)) {
        _accountPayloadClearInFlight = null;
        return;
      }
    }
  }

  static Future<bool?> _saveWidgetPayloadEntry(MapEntry<String, Object> entry) {
    final value = entry.value;
    if (value is bool) {
      return HomeWidget.saveWidgetData<bool>(entry.key, value);
    }
    if (value is int) {
      return HomeWidget.saveWidgetData<int>(entry.key, value);
    }
    return HomeWidget.saveWidgetData<String>(entry.key, value.toString());
  }

  static Future<bool> push({
    required int todoCount,
    required int habitPercent,
    required int pomodoroToday,
    required int focusMinutesToday,
    required BrandStrings strings,
    List<String> todoTop3 = const [],
    List<String> todoTop3Ids = const [],
    List<String> goalHighlights = const [],
    List<String> goalHighlightIds = const [],
    List<String> anniversaryHighlights = const [],
    List<String> anniversaryHighlightIds = const [],
    List<String> courseHighlights = const [],
    List<String> courseHighlightIds = const [],
    List<String> noteHighlights = const [],
    List<String> noteHighlightIds = const [],
    List<String> memorialHighlights = const [],
    List<String> memorialHighlightIds = const [],
    List<String> diaryHighlights = const [],
    List<String> diaryHighlightIds = const [],
    List<String> scheduleHighlights = const [],
    List<String> scheduleHighlightIds = const [],
    String todayEventSummary = '今日没有日程',
    String focusSummary = '今日还未专注',
    String habitSummary = '今日习惯待打卡',
    String streakSummary = '连续记录 0 天',
    String nextFocusLabel = '25 分钟专注',
    bool focusTimerRunning = false,
    int focusTimerRemainingSeconds = 0,
    int focusTimerTotalSeconds = 0,
    int focusTimerEndsAtMillis = 0,
    String focusTimerLabel = '专注倒计时',

    /// 正计时标记：原生按 `focus_timer_count_up` 切换 Chronometer。
    bool focusTimerCountUp = false,

    /// 控制身份：idle|running|paused + 不透明 session + revision + scope。
    String focusTimerState = 'idle',
    String focusTimerSessionId = '',
    int focusTimerRevision = 0,
    String focusControlScope = '',

    /// 全部今日可见未完成待办（已排序，不截 Top3）。
    String todoItemsJson = '[]',
    String habitQuickCheckId = '',
    String habitQuickCheckLabel = '点击进入习惯打卡',
    int habitTotalCompletions = 0,
    List<String> habitHighlights = const [],
    List<String> habitHighlightIds = const [],
    // 月历协议字段来自完整 todos 统计，与其它 payload 同批写入，
    // native 侧不会读到半新半旧的快照。
    Map<String, int> calendarDayCounts = const <String, int>{},
    String calendarTimezone = '',
    required HomeWidgetThemePayload theme,
  }) async {
    if (!_supported) return true;
    await _drainPendingAccountClear();
    final calendarPayload = _calendarPayload(
      dayCounts: calendarDayCounts,
      timezone: calendarTimezone,
    );
    // UI 纯展示文案：与数值/协议字段解耦，native 按 widget_* key 读取。
    final uiCopy = _widgetUiCopy(strings.navTodo);
    final signature = _pushSignature(
      todoCount: todoCount,
      habitPercent: habitPercent,
      pomodoroToday: pomodoroToday,
      focusMinutesToday: focusMinutesToday,
      strings: strings,
      todoTop3: todoTop3,
      todoTop3Ids: todoTop3Ids,
      goalHighlights: goalHighlights,
      goalHighlightIds: goalHighlightIds,
      anniversaryHighlights: anniversaryHighlights,
      anniversaryHighlightIds: anniversaryHighlightIds,
      courseHighlights: courseHighlights,
      courseHighlightIds: courseHighlightIds,
      noteHighlights: noteHighlights,
      noteHighlightIds: noteHighlightIds,
      memorialHighlights: memorialHighlights,
      memorialHighlightIds: memorialHighlightIds,
      diaryHighlights: diaryHighlights,
      diaryHighlightIds: diaryHighlightIds,
      scheduleHighlights: scheduleHighlights,
      scheduleHighlightIds: scheduleHighlightIds,
      todayEventSummary: todayEventSummary,
      focusSummary: focusSummary,
      habitSummary: habitSummary,
      streakSummary: streakSummary,
      nextFocusLabel: nextFocusLabel,
      focusTimerRunning: focusTimerRunning,
      focusTimerRemainingSeconds: focusTimerRemainingSeconds,
      focusTimerTotalSeconds: focusTimerTotalSeconds,
      focusTimerEndsAtMillis: focusTimerEndsAtMillis,
      focusTimerLabel: focusTimerLabel,
      focusTimerCountUp: focusTimerCountUp,
      focusTimerState: focusTimerState,
      focusTimerSessionId: focusTimerSessionId,
      focusTimerRevision: focusTimerRevision,
      focusControlScope: focusControlScope,
      todoItemsJson: todoItemsJson,
      habitQuickCheckId: habitQuickCheckId,
      habitQuickCheckLabel: habitQuickCheckLabel,
      habitTotalCompletions: habitTotalCompletions,
      habitHighlights: habitHighlights,
      habitHighlightIds: habitHighlightIds,
      theme: theme,
      calendar: calendarPayload,
      uiCopy: uiCopy,
    );
    if (signature == _lastPushSignature) return true;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<int>('todo_count', todoCount),
        HomeWidget.saveWidgetData<int>('habit_percent', habitPercent),
        HomeWidget.saveWidgetData<int>('pomodoro_today', pomodoroToday),
        HomeWidget.saveWidgetData<int>(
          'focus_minutes_today',
          focusMinutesToday,
        ),
        HomeWidget.saveWidgetData<String>('brand_app_title', strings.appTitle),
        HomeWidget.saveWidgetData<String>('nav_todo', strings.navTodo),
        HomeWidget.saveWidgetData<String>('nav_habit', strings.navHabit),
        HomeWidget.saveWidgetData<String>('nav_calendar', strings.navCalendar),
        HomeWidget.saveWidgetData<String>('nav_focus', strings.navFocus),
        // 今日待办 Top 3
        HomeWidget.saveWidgetData<int>('todo_top3_count', todoCount),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_1',
          todoTop3.isNotEmpty
              ? '· ${todoTop3[0]}'
              : I18n.tr('widget.todo_top3_empty'),
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_1_id',
          todoTop3Ids.isNotEmpty ? todoTop3Ids[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_2',
          todoTop3.length > 1 ? '· ${todoTop3[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_2_id',
          todoTop3Ids.length > 1 ? todoTop3Ids[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_3',
          todoTop3.length > 2 ? '· ${todoTop3[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_3_id',
          todoTop3Ids.length > 2 ? todoTop3Ids[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_1',
          goalHighlights.isNotEmpty ? '· ${goalHighlights[0]}' : '暂无进行中目标',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_1_id',
          goalHighlightIds.isNotEmpty ? goalHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_2',
          goalHighlights.length > 1 ? '· ${goalHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_2_id',
          goalHighlightIds.length > 1 ? goalHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_3',
          goalHighlights.length > 2 ? '· ${goalHighlights[2]}' : '本周目标保持推进',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_3_id',
          goalHighlightIds.length > 2 ? goalHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'anniversary_highlight_1',
          anniversaryHighlights.isNotEmpty
              ? '· ${anniversaryHighlights[0]}'
              : '暂无近期纪念日',
        ),
        HomeWidget.saveWidgetData<String>(
          'anniversary_highlight_1_id',
          anniversaryHighlightIds.isNotEmpty ? anniversaryHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'anniversary_highlight_2',
          anniversaryHighlights.length > 1
              ? '· ${anniversaryHighlights[1]}'
              : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'anniversary_highlight_2_id',
          anniversaryHighlightIds.length > 1 ? anniversaryHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_1',
          courseHighlights.isNotEmpty ? '· ${courseHighlights[0]}' : '今日暂无课程',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_1_id',
          courseHighlightIds.isNotEmpty ? courseHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_2',
          courseHighlights.length > 1 ? '· ${courseHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_2_id',
          courseHighlightIds.length > 1 ? courseHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_3',
          courseHighlights.length > 2 ? '· ${courseHighlights[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_3_id',
          courseHighlightIds.length > 2 ? courseHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_1',
          noteHighlights.isNotEmpty ? '· ${noteHighlights[0]}' : '暂无随手记',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_1_id',
          noteHighlightIds.isNotEmpty ? noteHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_2',
          noteHighlights.length > 1 ? '· ${noteHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_2_id',
          noteHighlightIds.length > 1 ? noteHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_3',
          noteHighlights.length > 2 ? '· ${noteHighlights[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_3_id',
          noteHighlightIds.length > 2 ? noteHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_1',
          memorialHighlights.isNotEmpty
              ? '· ${memorialHighlights[0]}'
              : '暂无近期纪念日',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_1_id',
          memorialHighlightIds.isNotEmpty ? memorialHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_2',
          memorialHighlights.length > 1 ? '· ${memorialHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_2_id',
          memorialHighlightIds.length > 1 ? memorialHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_3',
          memorialHighlights.length > 2 ? '· ${memorialHighlights[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_3_id',
          memorialHighlightIds.length > 2 ? memorialHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>('diary_highlight_1', ''),
        HomeWidget.saveWidgetData<String>('diary_highlight_1_id', ''),
        HomeWidget.saveWidgetData<String>('diary_highlight_2', ''),
        HomeWidget.saveWidgetData<String>('diary_highlight_2_id', ''),
        HomeWidget.saveWidgetData<String>('diary_highlight_3', ''),
        HomeWidget.saveWidgetData<String>('diary_highlight_3_id', ''),
        HomeWidget.saveWidgetData<String>(
          'today_event_summary',
          todayEventSummary,
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_1',
          scheduleHighlights.isNotEmpty
              ? '· ${scheduleHighlights[0]}'
              : '· $todayEventSummary',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_1_id',
          scheduleHighlightIds.isNotEmpty ? scheduleHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_2',
          scheduleHighlights.length > 1
              ? '· ${scheduleHighlights[1]}'
              : '· 打开日历查看完整安排',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_2_id',
          scheduleHighlightIds.length > 1 ? scheduleHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_3',
          scheduleHighlights.length > 2
              ? '· ${scheduleHighlights[2]}'
              : '提醒会跟随系统时区',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_3_id',
          scheduleHighlightIds.length > 2 ? scheduleHighlightIds[2] : '',
        ),
        ...calendarPayload.entries.map(_saveWidgetPayloadEntry),
        HomeWidget.saveWidgetData<String>('focus_summary', focusSummary),
        HomeWidget.saveWidgetData<String>('habit_summary', habitSummary),
        HomeWidget.saveWidgetData<String>('streak_summary', streakSummary),
        HomeWidget.saveWidgetData<String>('next_focus_label', nextFocusLabel),
        HomeWidget.saveWidgetData<bool>(
          'focus_timer_running',
          focusTimerRunning,
        ),
        HomeWidget.saveWidgetData<int>(
          'focus_timer_remaining_seconds',
          focusTimerRemainingSeconds,
        ),
        HomeWidget.saveWidgetData<int>(
          'focus_timer_total_seconds',
          focusTimerTotalSeconds,
        ),
        HomeWidget.saveWidgetData<int>(
          'focus_timer_ends_at_millis',
          focusTimerEndsAtMillis,
        ),
        HomeWidget.saveWidgetData<String>('focus_timer_label', focusTimerLabel),
        HomeWidget.saveWidgetData<bool>(
          'focus_timer_count_up',
          focusTimerCountUp,
        ),
        HomeWidget.saveWidgetData<String>('focus_timer_state', focusTimerState),
        HomeWidget.saveWidgetData<String>(
          'focus_timer_session_id',
          focusTimerSessionId,
        ),
        HomeWidget.saveWidgetData<int>(
          'focus_timer_revision',
          focusTimerRevision,
        ),
        HomeWidget.saveWidgetData<String>(
          'focus_control_scope',
          focusControlScope,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_todo_items_json',
          todoItemsJson,
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_quick_check_id',
          habitQuickCheckId,
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_quick_check_label',
          habitQuickCheckLabel,
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_highlight_1',
          habitHighlights.isNotEmpty ? habitHighlights[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_highlight_1_id',
          habitHighlightIds.isNotEmpty ? habitHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_highlight_2',
          habitHighlights.length > 1 ? habitHighlights[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_highlight_2_id',
          habitHighlightIds.length > 1 ? habitHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_highlight_3',
          habitHighlights.length > 2 ? habitHighlights[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_highlight_3_id',
          habitHighlightIds.length > 2 ? habitHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_todo_empty_hint',
          uiCopy['widget_todo_empty_hint']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_todo_count_unit',
          uiCopy['widget_todo_count_unit']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_habit_today_label',
          uiCopy['widget_habit_today_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_count_label',
          uiCopy['widget_focus_count_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_minutes_label',
          uiCopy['widget_focus_minutes_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_next_label',
          uiCopy['widget_focus_next_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_remaining_label',
          uiCopy['widget_focus_remaining_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_open_label',
          uiCopy['widget_focus_open_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_running_label',
          uiCopy['widget_focus_running_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_start_label',
          uiCopy['widget_focus_start_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_resume_label',
          uiCopy['widget_focus_resume_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_pause_label',
          uiCopy['widget_focus_pause_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_stop_label',
          uiCopy['widget_focus_stop_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_focus_paused_label',
          uiCopy['widget_focus_paused_label']!,
        ),
        HomeWidget.saveWidgetData<String>(
          'widget_today_label',
          uiCopy['widget_today_label']!,
        ),
        ...theme.saveOperations(),
      ]);
      final ok = await _updateAllWidgets();
      if (ok) {
        _lastPushSignature = signature;
        _lastThemeSignature = theme.signature;
      }
      return ok;
    } catch (e, st) {
      debugPrint('[HomeWidget] push failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> _updateAllWidgets() async {
    final refreshOverride = debugRefreshAllWidgetsOverride;
    if (PlatformInfo.isAndroid || refreshOverride != null) {
      final updated = refreshOverride != null
          ? await refreshOverride()
          : await AndroidWidgetManager.refreshAllWidgets();
      if (updated == null) {
        debugPrint('[HomeWidget] Android refreshAllWidgets failed');
        return false;
      }
      if (updated == 0) {
        // 0 命中说明没有任何桌面实例被重建（未添加小组件或 provider 未注册），
        // 不能当成功返回：否则 push() 会缓存 signature，后续同 payload 直接被
        // 去重丢掉，真机上表现为“新增任务后小组件不更新”。
        debugPrint('[HomeWidget] Android refreshAllWidgets updated 0 widgets');
        return false;
      }
      return true;
    }
    var ok = true;
    for (final target in _widgetUpdateTargets) {
      ok =
          await _updateWidgetFamily(
            androidName: target.androidName,
            iOSName: target.iOSName,
          ) &&
          ok;
    }
    if (!ok) {
      debugPrint('[HomeWidget] one or more widget providers failed to update');
    }
    return ok;
  }

  static Future<bool> _updateWidgetFamily({
    required String androidName,
    required String iOSName,
  }) async {
    var ok = true;
    Future<void> updateOne(String name, {String? ios}) async {
      try {
        await HomeWidget.updateWidget(
          name: name,
          androidName: name,
          iOSName: ios,
        );
      } catch (e, st) {
        ok = false;
        debugPrint('[HomeWidget] updateWidget($name) failed: $e\n$st');
      }
    }

    await updateOne(androidName, ios: iOSName);
    return ok;
  }

  /// 执行桌面小组件动作。
  ///
  /// 两个入口共用同一套动作规则：
  /// - 主 isolate 转发（[live] 非空）：直接写仍然存活的 Provider，payload 刷新
  ///   交给主 isolate 的常规推送，避免后台副本整表覆盖主 isolate 的改动；
  /// - 冷后台（[live] 为空）：先恢复应用时区与语言，再重新加载 Provider 执行，
  ///   成功后重算受影响的 payload 并刷新原生组件。
  ///
  /// 约束（两个入口一致）：
  /// - 只调用现有 Provider 方法写业务数据，不直接改 `todos` / `habits` 的 JSON，
  ///   因此 owner、存储 generation 与内存 Provider 的校验照旧生效；
  /// - 登录态或账号 owner 与当前账号不一致时 no-op，不写旧账号数据；
  /// - 后台没有 ScaffoldMessenger，失败只写 debug 日志。
  ///
  /// 返回是否真的写入了数据。
  static Future<bool> runBackgroundAction(
    HomeWidgetActionRequest request, {
    HomeWidgetLiveProviders? live,
    bool? signedIn,
  }) async {
    if (!_supported) return false;
    final cold = live == null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (cold) {
        // 后台引擎的 prefs 缓存可能停在上一个会话，先拉取最新值再判定边界。
        await prefs.reload();
        await _prepareColdIsolate();
      }
      final blocked = await _resolveBlockReason(
        prefs,
        signedIn: signedIn,
        request: request,
      );
      if (blocked != HomeWidgetActionBlockReason.none) {
        debugPrint(
          '[HomeWidget] ${request.kind.name} skipped: ${blocked.name}',
        );
        return false;
      }
      final providers = live ?? await _loadColdProviders();
      // Provider 加载期间可能发生切号/登出：写盘前用最新 prefs 再判定一次。
      final recheck = await _resolveBlockReason(
        prefs,
        signedIn: signedIn,
        request: request,
      );
      if (recheck != HomeWidgetActionBlockReason.none) {
        debugPrint(
          '[HomeWidget] ${request.kind.name} skipped: ${recheck.name}',
        );
        return false;
      }
      final changed = await _applyBackgroundAction(request, providers);
      if (!changed) return false;
      if (cold) {
        await providers.pomodoro.flushPersistence();
        // 冷引擎没有主 isolate 的监听链，这里补本地待同步元数据与 payload。
        _markColdLocalChange();
        await _refreshColdActionPayload(request.kind, providers);
      }
      return true;
    } catch (e, st) {
      debugPrint('[HomeWidget] ${request.kind.name} failed: $e\n$st');
      return false;
    }
  }

  /// 写入前的账号边界判定：读最新 prefs。
  ///
  /// [signedIn] 只在主 isolate 有内存登录态时传入，冷后台由 prefs 里的登录态决定。
  static Future<HomeWidgetActionBlockReason> _resolveBlockReason(
    SharedPreferences prefs, {
    bool? signedIn,
    HomeWidgetActionRequest? request,
  }) async {
    await prefs.reload();
    final scope = HomeWidgetAccountScope.fromPreferences(prefs);
    // 主 isolate 的内存登录态可能早于 prefs：未登录时按 signedOut 处理。
    final blocked = signedIn == false
        ? HomeWidgetActionBlockReason.signedOut
        : scope.blockReason;
    final currentScope = scope.focusControlScope;
    if (blocked == HomeWidgetActionBlockReason.none) {
      // 绑定 focus 控制必须属于当前账号 scope：换号后的旧按钮不能操作新账号。
      if (request != null &&
          request.isBoundFocusControl &&
          request.focusScope != currentScope) {
        return HomeWidgetActionBlockReason.ownerMismatch;
      }
      return HomeWidgetActionBlockReason.none;
    }
    // 只对合法的绑定 focus 请求放开匿名本地专注；legacy 无绑定请求仍按原规则。
    if (blocked == HomeWidgetActionBlockReason.signedOut &&
        request != null &&
        request.allowsSignedOutExecution &&
        currentScope == HomeWidgetAccountScope.localFocusControlScope &&
        request.focusScope == currentScope) {
      return HomeWidgetActionBlockReason.none;
    }
    return blocked;
  }

  /// 冷后台引擎的进程级初始化：应用时区与语言。
  ///
  /// 不初始化时区时 `AppClock` 会按系统时区算“今天”，打卡日期会偏移；
  /// 不恢复语言时小组件文案会回退到默认语言。
  static Future<void> _prepareColdIsolate() async {
    try {
      await LocalTimezoneResolver.init();
    } catch (e, st) {
      debugPrint('[HomeWidget] cold timezone init failed: $e\n$st');
    }
    try {
      await LocaleProvider().loadFromStorage();
    } catch (e, st) {
      debugPrint('[HomeWidget] cold locale restore failed: $e\n$st');
    }
  }

  static Future<HomeWidgetLiveProviders> _loadColdProviders() async {
    final providers = HomeWidgetLiveProviders(
      todos: TodoProvider(),
      habits: HabitProvider(),
      pomodoro: PomodoroProvider(),
    );
    await providers.todos.loadFromStorage();
    await providers.habits.loadFromStorage();
    await providers.pomodoro.loadFromStorage();
    return providers;
  }

  /// 冷后台写盘后补本地待同步标记（只写 prefs 元数据，不启动网络同步）。
  static void _markColdLocalChange() {
    try {
      final cloudSync = CloudSyncProvider();
      // 新建实例默认抑制脏标记，本次就是要记录“本地有改动”。
      cloudSync.dirtyMarkEnabled = true;
      cloudSync.markPendingLocalChange();
    } catch (e, st) {
      debugPrint('[HomeWidget] cold dirty metadata failed: $e\n$st');
    }
  }

  /// 冷后台动作后重算受影响的 payload，再请求原生组件刷新。
  static Future<void> _refreshColdActionPayload(
    HomeWidgetActionKind kind,
    HomeWidgetLiveProviders providers,
  ) async {
    try {
      final payload = buildHomeWidgetActionPayload(
        kind: kind,
        todos: providers.todos,
        habits: providers.habits,
        pomodoro: providers.pomodoro,
        focusControlScope: await currentFocusControlScope(),
      );
      // 顺序固定：先落 payload 再刷新原生组件，否则组件读到的是旧数据。
      await Future.wait(payload.entries.map(_saveWidgetPayloadEntry));
    } catch (e, st) {
      debugPrint('[HomeWidget] cold payload update failed: $e\n$st');
    }
    await _refreshWidgetsAfterAction(kind);
  }

  /// 后台动作的真实写入。目标实体不存在、已完成或不适用于桌面动作时不写。
  static Future<bool> _applyBackgroundAction(
    HomeWidgetActionRequest request,
    HomeWidgetLiveProviders providers,
  ) async {
    switch (request.kind) {
      case HomeWidgetActionKind.completeTodo:
        final id = request.targetId;
        if (id == null) return false;
        final todos = providers.todos;
        final target = todos.todos.where((todo) => todo.id == id).firstOrNull;
        if (homeWidgetTodoTargetState(target) !=
            HomeWidgetTodoTargetState.ready) {
          debugPrint('[HomeWidget] complete_todo skipped: target unavailable');
          return false;
        }
        return await todos.completeTodos([id]) > 0;
      case HomeWidgetActionKind.checkinHabit:
        final id = request.targetId;
        if (id == null) return false;
        final habits = providers.habits;
        final target = habits.habits
            .where((habit) => habit.id == id)
            .firstOrNull;
        if (homeWidgetHabitTargetState(target) !=
            HomeWidgetHabitTargetState.ready) {
          debugPrint('[HomeWidget] checkin_habit skipped: target unavailable');
          return false;
        }
        final habit = target!;
        final before = habit.todayCount();
        await habits.incrementHabit(id);
        return habit.todayCount() > before;
      case HomeWidgetActionKind.startPomodoro:
        return _applyFocusControl(
          providers.pomodoro,
          request,
          PomodoroWidgetControlAction.start,
        );
      case HomeWidgetActionKind.pausePomodoro:
        return _applyFocusControl(
          providers.pomodoro,
          request,
          PomodoroWidgetControlAction.pause,
        );
      case HomeWidgetActionKind.stopPomodoro:
        return _applyFocusControl(
          providers.pomodoro,
          request,
          PomodoroWidgetControlAction.stop,
        );
      case HomeWidgetActionKind.quickTodo:
        final text = request.text;
        if (text == null) return false;
        final todos = providers.todos;
        final before = todos.todos.length;
        await todos.addTodo(SmartTodoDraftBuilder.fromText(text).toTodo());
        return todos.todos.length > before;
    }
  }

  /// 专注控制执行。
  ///
  /// 绑定请求走 Provider 的 session + revision + state 校验（旧按钮/重复点击
  /// 一律 false 且不改状态）；legacy 无绑定 start 保持原有“仅在空闲时启动”。
  static Future<bool> _applyFocusControl(
    PomodoroProvider pomodoro,
    HomeWidgetActionRequest request,
    PomodoroWidgetControlAction action,
  ) async {
    if (request.isBoundFocusControl) {
      final sessionId = request.focusSessionId;
      final revision = request.focusRevision;
      final state = request.focusState;
      if (sessionId == null || revision == null || state == null) return false;
      return pomodoro.applyWidgetControl(
        action: action,
        sessionId: sessionId,
        revision: revision,
        expectedState: state,
      );
    }
    if (action != PomodoroWidgetControlAction.start) return false;
    if (pomodoro.state.isRunning) return false;
    pomodoro.startIfIdle();
    return pomodoro.state.isRunning;
  }

  /// 桌面动作之后需要重算的小组件 payload。
  ///
  /// 只包含被动作影响的键，避免覆盖主题、日程等无关内容；取值规则必须与
  /// `main.dart` 的 `_pushHomeWidget` 一致，否则后台动作后小组件会跳变。
  @visibleForTesting
  static Map<String, Object> buildHomeWidgetActionPayload({
    required HomeWidgetActionKind kind,
    required TodoProvider todos,
    required HabitProvider habits,
    required PomodoroProvider pomodoro,
    DateTime? now,

    /// 当前账号/匿名 focus 控制 scope（冷后台从 prefs 读取后传入）。
    String focusControlScope = '',
  }) {
    switch (kind) {
      case HomeWidgetActionKind.completeTodo:
      case HomeWidgetActionKind.quickTodo:
        return todoHomeWidgetActionPayload(todos, now: now);
      case HomeWidgetActionKind.checkinHabit:
        return habitHomeWidgetActionPayload(habits);
      case HomeWidgetActionKind.startPomodoro:
      case HomeWidgetActionKind.pausePomodoro:
      case HomeWidgetActionKind.stopPomodoro:
        return <String, Object>{
          ...focusHomeWidgetActionPayload(
            pomodoro,
            focusControlScope: focusControlScope,
          ),
          ...todoHomeWidgetActionPayload(todos, now: now),
        };
    }
  }

  /// 待办相关 payload：与 `_pushHomeWidget` 的可见性/排序一致。
  @visibleForTesting
  static Map<String, Object> todoHomeWidgetActionPayload(
    TodoProvider todos, {
    DateTime? now,
  }) {
    final nowTs = now ?? AppClock.now();
    // 与 `_pushHomeWidget` 完全同口径：四象限 Q1→Q3→Q2→Q4、同象限优先级倒序、
    // 手动次序、创建时刻与 ID 稳定兜底；原生只读这份已排序数组，不再自排。
    final visible = buildHomeWidgetTodoItems(
      todos.visibleTodayTodos(nowTs),
      now: nowTs,
    );
    final top3 = visible.take(3).toList();
    return <String, Object>{
      'todo_count': visible.length,
      'todo_top3_count': visible.length,
      'widget_todo_items_json': encodeHomeWidgetTodoItems(visible),
      'todo_top3_1': top3.isNotEmpty
          ? '· ${top3[0].title}'
          : I18n.tr('widget.todo_top3_empty'),
      'todo_top3_1_id': top3.isNotEmpty ? top3[0].id : '',
      'todo_top3_2': top3.length > 1 ? '· ${top3[1].title}' : '',
      'todo_top3_2_id': top3.length > 1 ? top3[1].id : '',
      'todo_top3_3': top3.length > 2 ? '· ${top3[2].title}' : '',
      'todo_top3_3_id': top3.length > 2 ? top3[2].id : '',
      'calendar_day_counts_json': homeWidgetCalendarDayCountsJson(
        buildHomeWidgetCalendarDayCounts(todos.todos),
      ),
      'calendar_timezone': LocalTimezoneResolver.currentIana,
      'calendar_weekdays_json': homeWidgetCalendarWeekdayLabelsJson(),
      'calendar_day_count_label': I18n.tr('widget.calendar_day_count_label'),
      'calendar_month_title': I18n.tr('widget.calendar_month_title'),
      ..._widgetUiCopy(I18n.tr('nav.todo')),
    };
  }

  /// 习惯相关 payload：完成率、摘要与“下一项快捷打卡”。
  static Map<String, Object> habitHomeWidgetActionPayload(
    HabitProvider habits,
  ) {
    final percent = (habits.todayCompletionRate * 100).round();
    final active =
        habits.habits.where((habit) => habit.isActiveToday()).toList()
          ..sort((a, b) {
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            if (byOrder != 0) return byOrder;
            return a.createdAt.compareTo(b.createdAt);
          });
    final pending = active
        .where(
          (habit) =>
              habit.kind == HabitKind.positive && !habit.isCompletedToday(),
        )
        .toList();
    final quick = pending.isEmpty ? null : pending.first;
    final highlights = active
        .take(3)
        .map(
          (habit) =>
              '· ${habit.name} ${(habit.todayProgress() * 100).round()}%',
        )
        .toList();
    final highlightIds = active.take(3).map((habit) => habit.id).toList();
    return <String, Object>{
      'habit_percent': percent,
      'habit_summary': percent >= 100
          ? I18n.tr('widget.habit_all_done')
          : '${I18n.tr('widget.habit_progress_prefix')}$percent'
                '${I18n.tr('widget.habit_progress_suffix')}',
      'habit_quick_check_id': quick?.id ?? '',
      'habit_quick_check_label': quick == null
          ? I18n.tr('widget.habit_quick_check_hint')
          : '${I18n.tr('widget.habit_checkin_prefix')}${quick.name}',
      'habit_highlight_1': highlights.isNotEmpty ? highlights[0] : '',
      'habit_highlight_1_id': highlightIds.isNotEmpty ? highlightIds[0] : '',
      'habit_highlight_2': highlights.length > 1 ? highlights[1] : '',
      'habit_highlight_2_id': highlightIds.length > 1 ? highlightIds[1] : '',
      'habit_highlight_3': highlights.length > 2 ? highlights[2] : '',
      'habit_highlight_3_id': highlightIds.length > 2 ? highlightIds[2] : '',
    };
  }

  /// 专注相关 payload：倒计时毫秒用真实 `DateTime.now()` 计算，与主推送一致。
  @visibleForTesting
  static Map<String, Object> focusHomeWidgetActionPayload(
    PomodoroProvider pomodoro, {
    String focusControlScope = '',
  }) {
    final state = pomodoro.state;
    // 结束时刻必须用 Provider 的 canonical 锚点，不能用 now + remaining 每推漂移；
    // 正计时为 0，原生据 `focus_timer_count_up` 改用 Chronometer。
    final endsAtMillis = pomodoro.focusTimerEndsAtMillis;
    final label = switch (state.type) {
      PomodoroType.focus =>
        state.isCountUp
            ? I18n.tr('widget.focus_counting_up')
            : I18n.tr('widget.focus_countdown'),
      PomodoroType.shortBreak => I18n.tr('widget.short_break_countdown'),
      PomodoroType.longBreak => I18n.tr('widget.long_break_countdown'),
    };
    final sessions = pomodoro.sessionCountToday;
    return <String, Object>{
      'focus_timer_running': state.isRunning,
      'focus_timer_remaining_seconds': state.remainingSeconds,
      'focus_timer_total_seconds': state.totalSeconds,
      'focus_timer_ends_at_millis': endsAtMillis,
      'focus_timer_label': label,
      'focus_timer_count_up': state.isCountUp,
      'focus_timer_state': pomodoro.focusTimerState.wireName,
      'focus_timer_session_id': pomodoro.focusControlSessionId,
      'focus_timer_revision': pomodoro.focusControlRevision,
      'focus_control_scope': focusControlScope,
      'focus_summary': sessions == 0
          ? I18n.tr('widget.focus_not_started')
          : '${I18n.tr('widget.focus_today_prefix')}$sessions'
                '${I18n.tr('widget.focus_today_suffix')}',
    };
  }

  static Future<void> _refreshWidgetsAfterAction(
    HomeWidgetActionKind kind,
  ) async {
    if (!_androidBackgroundSupported) return;
    for (final providerName in androidProviderNamesForAction(kind)) {
      try {
        // 走 home_widget 原生通道：后台 isolate 没有主 isolate 的
        // `duoyi/widgets` 通道，`AndroidWidgetManager` 在那里不可用。
        await HomeWidget.updateWidget(
          name: providerName,
          androidName: providerName,
        );
      } catch (e, st) {
        debugPrint('[HomeWidget] refresh $providerName failed: $e\n$st');
      }
    }
  }

  /// 冷后台动作后需要重绘的原生小组件类名。
  ///
  /// 4 个核心页（待办 / 习惯 / 日历 / 专注）在原生侧支持按实例切换内容：
  /// 历史综合小组件、习惯宿主都可能正显示待办页，所以任一动作都要刷新全部
  /// 13 个唯一 provider（核心 4 类 × 标准/compact/detailed + 历史综合）。
  @visibleForTesting
  static List<String> androidProviderNamesForAction(HomeWidgetActionKind kind) {
    // kind 参数保留以兼容现有调用；实例内切页让四个宿主互相可能显示同一页。
    const coreProviders = [
      _androidTodoProviderName,
      _androidHabitProviderName,
      _androidCalendarProviderName,
      _androidFocusProviderName,
    ];
    return [
      for (final provider in coreProviders) ...[
        provider,
        ..._androidWidgetVariants(provider),
      ],
      // 历史综合组件同样支持实例内切页，必须一起刷新。
      'DuoyiWidgetProvider',
    ];
  }

  static List<String> _androidWidgetVariants(String provider) {
    if (provider == 'DuoyiWidgetProvider') return const <String>[];
    return [
      provider.replaceFirst('WidgetProvider', 'CompactWidgetProvider'),
      provider.replaceFirst('WidgetProvider', 'DetailedWidgetProvider'),
    ];
  }

  /// 当前账号/匿名 focus 控制 scope：无身份时返回空串（原生视为不可控制）。
  static Future<String> currentFocusControlScope() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return HomeWidgetAccountScope.fromPreferences(prefs).focusControlScope ??
          '';
    } catch (e, st) {
      debugPrint('[HomeWidget] focus scope read failed: $e\n$st');
      return '';
    }
  }

  static Stream<Uri?> get widgetClickedStream {
    if (!_supported) return const Stream.empty();
    return HomeWidget.widgetClicked;
  }

  static Future<Uri?> initialLaunchUri() async {
    if (!_supported) return null;
    return HomeWidget.initiallyLaunchedFromHomeWidget();
  }

  static String _pushSignature({
    required int todoCount,
    required int habitPercent,
    required int pomodoroToday,
    required int focusMinutesToday,
    required BrandStrings strings,
    required List<String> todoTop3,
    required List<String> todoTop3Ids,
    required List<String> goalHighlights,
    required List<String> goalHighlightIds,
    required List<String> anniversaryHighlights,
    required List<String> anniversaryHighlightIds,
    required List<String> courseHighlights,
    required List<String> courseHighlightIds,
    required List<String> noteHighlights,
    required List<String> noteHighlightIds,
    required List<String> memorialHighlights,
    required List<String> memorialHighlightIds,
    required List<String> diaryHighlights,
    required List<String> diaryHighlightIds,
    required List<String> scheduleHighlights,
    required List<String> scheduleHighlightIds,
    required String todayEventSummary,
    required String focusSummary,
    required String habitSummary,
    required String streakSummary,
    required String nextFocusLabel,
    required bool focusTimerRunning,
    required int focusTimerRemainingSeconds,
    required int focusTimerTotalSeconds,
    required int focusTimerEndsAtMillis,
    required String focusTimerLabel,
    required bool focusTimerCountUp,
    required String focusTimerState,
    required String focusTimerSessionId,
    required int focusTimerRevision,
    required String focusControlScope,
    required String todoItemsJson,
    required String habitQuickCheckId,
    required String habitQuickCheckLabel,
    required int habitTotalCompletions,
    required List<String> habitHighlights,
    required List<String> habitHighlightIds,
    required HomeWidgetThemePayload theme,
    required Map<String, Object> calendar,
    required Map<String, String> uiCopy,
  }) {
    return [
      todoCount,
      habitPercent,
      pomodoroToday,
      focusMinutesToday,
      strings.appTitle,
      strings.navTodo,
      strings.navHabit,
      strings.navCalendar,
      strings.navFocus,
      _listSignature(todoTop3),
      _listSignature(todoTop3Ids),
      _listSignature(goalHighlights),
      _listSignature(goalHighlightIds),
      _listSignature(anniversaryHighlights),
      _listSignature(anniversaryHighlightIds),
      _listSignature(courseHighlights),
      _listSignature(courseHighlightIds),
      _listSignature(noteHighlights),
      _listSignature(noteHighlightIds),
      _listSignature(memorialHighlights),
      _listSignature(memorialHighlightIds),
      _listSignature(diaryHighlights),
      _listSignature(diaryHighlightIds),
      _listSignature(scheduleHighlights),
      _listSignature(scheduleHighlightIds),
      todayEventSummary,
      focusSummary,
      habitSummary,
      streakSummary,
      nextFocusLabel,
      focusTimerRunning,
      focusTimerRemainingSeconds,
      focusTimerTotalSeconds,
      focusTimerEndsAtMillis,
      focusTimerLabel,
      focusTimerCountUp,
      focusTimerState,
      focusTimerSessionId,
      focusTimerRevision,
      focusControlScope,
      todoItemsJson,
      habitQuickCheckId,
      habitQuickCheckLabel,
      habitTotalCompletions,
      _listSignature(habitHighlights),
      _listSignature(habitHighlightIds),
      theme.signature,
      calendar['calendar_day_counts_json'],
      calendar['calendar_timezone'],
      calendar['calendar_weekdays_json'],
      calendar['calendar_day_count_label'],
      calendar['calendar_month_title'],
      calendar['calendar_month_summary'],
      // UI 纯展示文案：locale 切换只改 copy 也必须刷新原生组件。
      uiCopy.entries.map((entry) => '${entry.key}=${entry.value}').join(','),
    ].map(_signaturePart).join('|');
  }

  /// 月历协议字段（原生代理按此读取）。
  ///
  /// `calendar_day_counts_json` 覆盖全部任务日期（不限当月），native 侧可随当前
  /// 月份滚动取值；`calendar_weekdays_json` 是周一..周日表头；
  /// `calendar_day_count_label` 是含 `{date}` / `{count}` 的角标模板。
  static Map<String, Object> _calendarPayload({
    required Map<String, int> dayCounts,
    required String timezone,
  }) => <String, Object>{
    'calendar_day_counts_json': homeWidgetCalendarDayCountsJson(dayCounts),
    'calendar_timezone': timezone,
    'calendar_weekdays_json': homeWidgetCalendarWeekdayLabelsJson(),
    'calendar_day_count_label': I18n.tr('widget.calendar_day_count_label'),
    'calendar_month_title': I18n.tr('widget.calendar_month_title'),
    'calendar_month_summary': I18n.tr('widget.calendar_month_summary'),
  };

  /// 桌面小组件 UI 纯展示文案。
  ///
  /// native 子布局按 `widget_*` key 读取这些字符串，与数值/协议字段解耦：
  /// 换语言只改这份 copy，不影响任务、倒计时与月历协议。`{tab}` 用当前
  /// 导航模块名替换（常规推送用品牌词，账号兜底/冷态用默认词）。
  static Map<String, String> _widgetUiCopy(String navTodoLabel) =>
      <String, String>{
        'widget_todo_empty_hint': _todoEmptyHint(navTodoLabel),
        'widget_todo_count_unit': I18n.tr('widget.todo_count_unit'),
        'widget_habit_today_label': I18n.tr('widget.habit_today_label'),
        'widget_focus_count_label': I18n.tr('widget.focus_count_label'),
        'widget_focus_minutes_label': I18n.tr('widget.focus_minutes_label'),
        'widget_focus_next_label': I18n.tr('widget.focus_next_label'),
        'widget_focus_remaining_label': I18n.tr('widget.focus_remaining_label'),
        'widget_focus_open_label': I18n.tr('widget.focus_open_label'),
        'widget_focus_running_label': I18n.tr('widget.focus_running_label'),
        'widget_focus_start_label': I18n.tr('widget.focus_start_label'),
        'widget_focus_resume_label': I18n.tr('widget.focus_resume_label'),
        'widget_focus_pause_label': I18n.tr('widget.focus_pause_label'),
        'widget_focus_stop_label': I18n.tr('widget.focus_stop_label'),
        'widget_focus_paused_label': I18n.tr('widget.focus_paused_label'),
        'widget_today_label': I18n.tr('widget.today_label'),
      };

  /// 待办空态提示：把 `{tab}` 换成待办导航词（品牌词或默认词）。
  static String _todoEmptyHint(String navTodoLabel) =>
      I18n.tr('widget.todo_empty_hint').replaceAll('{tab}', navTodoLabel);

  static String _listSignature(List<String> values) {
    return values.map(_signaturePart).join(',');
  }

  static String _signaturePart(Object? value) {
    final text = value?.toString() ?? '';
    return '${text.length}:$text';
  }
}

class HomeWidgetThemePayload {
  final String brandId;
  final String cardSkinId;
  final bool dark;
  final Color primary;
  final Color background;
  final Color surface;
  final Color navBackground;
  final Color border;
  final Color text;
  final Color mutedText;
  final Color onPrimary;
  final Color accentStart;
  final Color accentEnd;
  final String backgroundAssetKey;
  final int cornerRadiusDp;
  final int controlRadiusDp;
  final int borderWidthDp;

  const HomeWidgetThemePayload({
    required this.brandId,
    required this.cardSkinId,
    required this.dark,
    required this.primary,
    required this.background,
    required this.surface,
    required this.navBackground,
    required this.border,
    required this.text,
    required this.mutedText,
    required this.onPrimary,
    required this.accentStart,
    required this.accentEnd,
    required this.backgroundAssetKey,
    required this.cornerRadiusDp,
    required this.controlRadiusDp,
    required this.borderWidthDp,
  });

  factory HomeWidgetThemePayload.fromThemeProvider(ThemeProvider provider) {
    final brand = provider.activeWidgetBackgroundBrand;
    final theme = brand.theme;
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final cardSkin = provider.activeWidgetCardSkin;
    final usesCardSkin = cardSkin.id != ThemeProvider.defaultCardSkinId;
    final imageBacked = brand.backgroundAsset != null;
    final accentStart = usesCardSkin ? cardSkin.colors.first : cs.primary;
    final accentEnd = usesCardSkin ? cardSkin.colors.last : cs.secondary;
    final baseBackground = Color.alphaBlend(
      brand.backgroundOverlay.withValues(
        alpha: imageBacked
            ? brand.backgroundOverlayOpacity.clamp(0.56, 0.82).toDouble()
            : brand.backgroundOverlayOpacity,
      ),
      dark ? const Color(0xFF0B0F17) : const Color(0xFFFFFFFF),
    );
    final background = Color.alphaBlend(
      accentEnd.withValues(alpha: imageBacked ? (dark ? 0.22 : 0.14) : 0.08),
      Color.alphaBlend(
        accentStart.withValues(alpha: dark ? 0.22 : 0.12),
        baseBackground,
      ),
    );
    final surface = Color.alphaBlend(
      accentEnd.withValues(
        alpha: usesCardSkin
            ? (dark ? 0.24 : 0.16)
            : imageBacked
            ? (dark ? 0.16 : 0.09)
            : 0.06,
      ),
      Color.alphaBlend(
        brand.backgroundOverlay.withValues(alpha: imageBacked ? 0.18 : 0.0),
        cs.surface,
      ),
    );
    final navBackground = Color.alphaBlend(
      cs.primary.withValues(alpha: imageBacked ? (dark ? 0.24 : 0.12) : 0.10),
      surface,
    );
    final border = Color.alphaBlend(
      accentStart.withValues(alpha: usesCardSkin ? (dark ? 0.50 : 0.34) : 0.18),
      cs.outlineVariant,
    );
    final cornerRadiusDp = switch (cardSkin.id) {
      'paper_card' => 14,
      'mint_card' => 15,
      'starlight_card' => 16,
      _ => 13,
    };
    return HomeWidgetThemePayload(
      brandId: brand.id,
      cardSkinId: cardSkin.id,
      dark: dark,
      primary: cs.primary,
      background: background,
      surface: surface,
      navBackground: navBackground,
      border: border,
      text: cs.onSurface,
      mutedText: cs.onSurfaceVariant,
      onPrimary: cs.onPrimary,
      accentStart: accentStart,
      accentEnd: accentEnd,
      backgroundAssetKey: _backgroundAssetKey(brand.backgroundAsset),
      cornerRadiusDp: cornerRadiusDp,
      controlRadiusDp: 8,
      borderWidthDp: usesCardSkin ? 1 : 0,
    );
  }

  List<Future<bool?>> saveOperations() => [
    HomeWidget.saveWidgetData<String>('widget_theme_brand_id', brandId),
    HomeWidget.saveWidgetData<String>('widget_theme_card_skin_id', cardSkinId),
    HomeWidget.saveWidgetData<bool>('widget_theme_dark', dark),
    HomeWidget.saveWidgetData<String>('widget_theme_primary', _hex(primary)),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_background',
      _hex(background),
    ),
    HomeWidget.saveWidgetData<String>('widget_theme_surface', _hex(surface)),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_nav_background',
      _hex(navBackground),
    ),
    HomeWidget.saveWidgetData<String>('widget_theme_border', _hex(border)),
    HomeWidget.saveWidgetData<String>('widget_theme_text', _hex(text)),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_muted_text',
      _hex(mutedText),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_on_primary',
      _hex(onPrimary),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_accent_start',
      _hex(accentStart),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_accent_end',
      _hex(accentEnd),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_background_asset_key',
      backgroundAssetKey,
    ),
    HomeWidget.saveWidgetData<int>(
      'widget_theme_corner_radius_dp',
      cornerRadiusDp,
    ),
    HomeWidget.saveWidgetData<int>(
      'widget_theme_control_radius_dp',
      controlRadiusDp,
    ),
    HomeWidget.saveWidgetData<int>(
      'widget_theme_border_width_dp',
      borderWidthDp,
    ),
  ];

  String get signature {
    return [
      brandId,
      cardSkinId,
      dark,
      _hex(primary),
      _hex(background),
      _hex(surface),
      _hex(navBackground),
      _hex(border),
      _hex(text),
      _hex(mutedText),
      _hex(onPrimary),
      _hex(accentStart),
      _hex(accentEnd),
      backgroundAssetKey,
      cornerRadiusDp,
      controlRadiusDp,
      borderWidthDp,
    ].map(HomeWidgetService._signaturePart).join('|');
  }

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static String _backgroundAssetKey(String? asset) {
    return switch (asset) {
      'assets/backgrounds/re0.png' => 're0',
      'assets/backgrounds/genshin.png' => 'genshin',
      'assets/backgrounds/star_rail.png' => 'star_rail',
      'assets/backgrounds/wuthering.png' => 'wuthering',
      'assets/backgrounds/zzz.png' => 'zzz',
      'assets/backgrounds/yanyun.png' => 'yanyun',
      'assets/backgrounds/botw.png' => 'botw',
      _ => '',
    };
  }
}

class _HomeWidgetUpdateTarget {
  final String androidName;
  final String iOSName;

  const _HomeWidgetUpdateTarget({
    required this.androidName,
    required this.iOSName,
  });
}

const List<_HomeWidgetUpdateTarget> _widgetUpdateTargets = [
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidTodoProviderName,
    iOSName: HomeWidgetService._iosTodoWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidFocusProviderName,
    iOSName: HomeWidgetService._iosFocusWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidHabitProviderName,
    iOSName: HomeWidgetService._iosHabitWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidCalendarProviderName,
    iOSName: HomeWidgetService._iosCalendarWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidScheduleProviderName,
    iOSName: HomeWidgetService._iosScheduleWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidGoalProviderName,
    iOSName: HomeWidgetService._iosGoalWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidCourseProviderName,
    iOSName: HomeWidgetService._iosCourseWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidNoteProviderName,
    iOSName: HomeWidgetService._iosNoteWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidAnniversaryProviderName,
    iOSName: HomeWidgetService._iosAnniversaryWidgetName,
  ),
];

/// 桌面小组件后台动作入口。
///
/// `home_widget` 的 `HomeWidgetBackgroundReceiver`（见 `AndroidManifest.xml`）
/// 会把它交给独立的 FlutterEngine 执行，因此这里拿不到主 isolate 的 Provider、
/// BuildContext 或 Navigator：只做数据变更与原生小组件刷新，不触发页面导航。
///
/// 主 isolate 还活着时先转发过去：那里有唯一可信的内存 Provider，避免后台
/// 副本用陈旧数据整表覆盖主 isolate 的改动。转发结果（含失败/超时）都视为
/// “已被接管”，不再本地重跑，防止重复写盘与重复打卡。
@visibleForTesting
Future<void> handleHomeWidgetBackgroundUri(
  Uri? uri, {
  Future<bool> Function(Uri uri)? forwardToMain,
  Future<bool> Function(HomeWidgetActionRequest request)? runLocally,
}) async {
  final request = HomeWidgetActionRequest.parse(uri);
  if (request == null || uri == null) {
    // URI 可能带用户输入文本，日志只记录 host，不打印完整链接。
    debugPrint('[HomeWidget] background callback ignored: ${uri?.host ?? '-'}');
    return;
  }
  final forwarded =
      await (forwardToMain ?? HomeWidgetActionBridge.forwardToMainIsolate)(uri);
  if (forwarded) return;
  await (runLocally ?? HomeWidgetService.runBackgroundAction)(request);
}

@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) =>
    handleHomeWidgetBackgroundUri(uri);
