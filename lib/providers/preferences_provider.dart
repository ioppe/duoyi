import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_text_scale.dart';
import '../core/local_timezone_resolver.dart';
import '../core/notification_history_policy.dart';
import '../core/report_reminder_config.dart';
import '../core/server_connection.dart';
import '../core/web_target.dart';
import '../models/goal.dart' show ReminderKind;

class DailyReminderSlot {
  final bool enabled;
  final ReminderKind kind;
  final int hour;
  final int minute;
  final bool includeTodayTasks;
  final bool includeTomorrowPlan;
  final bool includeOverdue;
  final List<int> repeatDays;
  final bool pauseHolidays;

  const DailyReminderSlot({
    this.enabled = false,
    this.kind = ReminderKind.push,
    this.hour = 20,
    this.minute = 0,
    this.includeTodayTasks = true,
    this.includeTomorrowPlan = true,
    this.includeOverdue = true,
    this.repeatDays = const [1, 2, 3, 4, 5, 6, 7],
    this.pauseHolidays = false,
  });

  DailyReminderSlot copyWith({
    bool? enabled,
    ReminderKind? kind,
    int? hour,
    int? minute,
    bool? includeTodayTasks,
    bool? includeTomorrowPlan,
    bool? includeOverdue,
    List<int>? repeatDays,
    bool? pauseHolidays,
  }) {
    final nextKind = normalizeKind(kind ?? this.kind);
    return DailyReminderSlot(
      enabled: nextKind == ReminderKind.off ? false : enabled ?? this.enabled,
      kind: nextKind,
      hour: (hour ?? this.hour).clamp(0, 23),
      minute: (minute ?? this.minute).clamp(0, 59),
      includeTodayTasks: includeTodayTasks ?? this.includeTodayTasks,
      includeTomorrowPlan: includeTomorrowPlan ?? this.includeTomorrowPlan,
      includeOverdue: includeOverdue ?? this.includeOverdue,
      repeatDays: _normalizeDays(repeatDays ?? this.repeatDays),
      pauseHolidays: pauseHolidays ?? this.pauseHolidays,
    );
  }

  static List<int> _normalizeDays(List<int> days) {
    final normalized = days.where((d) => d >= 1 && d <= 7).toSet().toList()
      ..sort();
    return normalized.isEmpty ? const [1, 2, 3, 4, 5, 6, 7] : normalized;
  }

  static ReminderKind normalizeKind(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.push || ReminderKind.popup || ReminderKind.alarm => kind,
      ReminderKind.off => ReminderKind.off,
      ReminderKind.email => ReminderKind.push,
    };
  }

  static ReminderKind parseKind(String? raw) {
    if (raw == null || raw.trim().isEmpty) return ReminderKind.push;
    for (final kind in ReminderKind.values) {
      if (kind.name == raw) return normalizeKind(kind);
    }
    return ReminderKind.push;
  }
}

bool _sameDailyReminderSlot(DailyReminderSlot a, DailyReminderSlot b) {
  final left = a.copyWith();
  final right = b.copyWith();
  return left.enabled == right.enabled &&
      left.kind == right.kind &&
      left.hour == right.hour &&
      left.minute == right.minute &&
      left.includeTodayTasks == right.includeTodayTasks &&
      left.includeTomorrowPlan == right.includeTomorrowPlan &&
      left.includeOverdue == right.includeOverdue &&
      listEquals(left.repeatDays, right.repeatDays) &&
      left.pauseHolidays == right.pauseHolidays;
}

class DailyReminderScheduleSlot {
  final int index;
  final DailyReminderSlot slot;

  const DailyReminderScheduleSlot({required this.index, required this.slot});
}

List<DailyReminderScheduleSlot> effectiveDailyReminderScheduleSlots(
  List<DailyReminderSlot> slots,
) {
  final result = <DailyReminderScheduleSlot>[];
  final claimedDaysByWallClock = <String, Set<int>>{};

  for (var index = 0; index < slots.length; index++) {
    final slot = slots[index];
    final kind = DailyReminderSlot.normalizeKind(slot.kind);
    if (!slot.enabled || kind == ReminderKind.off) continue;

    final repeatDays = DailyReminderSlot._normalizeDays(slot.repeatDays);
    final wallClockKey = '${slot.hour}:${slot.minute}';
    final claimedDays = claimedDaysByWallClock.putIfAbsent(
      wallClockKey,
      () => <int>{},
    );
    final remainingDays = repeatDays
        .where((day) => !claimedDays.contains(day))
        .toList(growable: false);
    if (remainingDays.isEmpty) continue;

    claimedDays.addAll(remainingDays);
    result.add(
      DailyReminderScheduleSlot(
        index: index,
        slot: slot.copyWith(kind: kind, repeatDays: remainingDays),
      ),
    );
  }

  return result;
}

/// 用户个性化偏好(本地)。不涉及服务器配置，每个设备独立。
class PreferencesProvider extends ChangeNotifier {
  static const maxBottomNavTabs = 5;
  static const fixedBottomNavTabs = <int>{6};
  static const mobileDefaultBottomNavTabs = <int>{0, 1, 2, 4, 6};
  static const webDefaultBottomNavTabs = <int>{0, 1, 2, 4, 6};
  static Set<int> get defaultBottomNavTabs => WebTarget.isWebBuild
      ? webDefaultBottomNavTabs
      : mobileDefaultBottomNavTabs;
  static bool isBottomNavTabSupported(int tab) =>
      !(WebTarget.isWebBuild && tab == 5);
  static int normalizeDefaultTab(int tab) {
    final normalized = tab.clamp(0, 6).toInt();
    return isBottomNavTabSupported(normalized) ? normalized : 0;
  }

  static const _kFirstDayOfWeek = 'pref_first_day_of_week';
  static const _kDateFormat = 'pref_date_format';
  static const _kDefaultTab = 'pref_default_tab';
  static const _kHapticFeedback = 'pref_haptic_feedback';
  static const _kShowLunar = 'pref_show_lunar';
  static const _kShowHomeCalendar = 'pref_show_home_calendar';
  static const _kShowCompletedTodos = 'pref_show_completed_todos';
  static const _kDefaultPomodoroMinutes = 'pref_default_pomodoro_minutes';
  static const _kQuickCaptureFab = 'pref_quick_capture_fab';
  static const _kNotificationQuickAdd = 'pref_notification_quick_add';
  static const _kNotificationTodayProgress = 'pref_notification_today_progress';
  static const _kNotificationHistoryLimit =
      NotificationHistoryPolicy.preferenceKey;
  static const _kAutoArchiveCompletedDays = 'pref_auto_archive_completed_days';
  static const _kDailyReminderEnabled = 'pref_daily_reminder_enabled';
  static const _kDailyReminderKind = 'pref_daily_reminder_kind';
  static const _kDailyReminderHour = 'pref_daily_reminder_hour';
  static const _kDailyReminderMinute = 'pref_daily_reminder_minute';
  static const _kDailyReminderIncludeTodayTasks =
      'pref_daily_reminder_today_tasks';
  static const _kDailyReminderIncludeTomorrowPlan =
      'pref_daily_reminder_tomorrow_plan';
  static const _kDailyReminderIncludeOverdue = 'pref_daily_reminder_overdue';
  static const _kDailyReminderRepeatDays = 'pref_daily_reminder_repeat_days';
  static const _kDailyReminderPauseHolidays =
      'pref_daily_reminder_pause_holidays';
  static const _kDailyReminderSlotPrefix = 'pref_daily_reminder_slot';
  static const _kDailyReportReminder = 'pref_daily_report_reminder';
  static const _kDailyReportReminderHour = 'pref_daily_report_reminder_hour';
  static const _kDailyReportReminderMinute =
      'pref_daily_report_reminder_minute';
  static const _kWeeklyReportReminder = 'pref_weekly_report_reminder';
  static const _kWeeklyReportReminderWeekday =
      'pref_weekly_report_reminder_weekday';
  static const _kWeeklyReportReminderHour = 'pref_weekly_report_reminder_hour';
  static const _kWeeklyReportReminderMinute =
      'pref_weekly_report_reminder_minute';
  static const _kMonthlyReportReminder = 'pref_monthly_report_reminder';
  static const _kMonthlyReportReminderDay = 'pref_monthly_report_reminder_day';
  static const _kMonthlyReportReminderHour =
      'pref_monthly_report_reminder_hour';
  static const _kMonthlyReportReminderMinute =
      'pref_monthly_report_reminder_minute';
  static const _kYearlyReportReminder = 'pref_yearly_report_reminder';
  static const _kYearlyReportReminderMonth =
      'pref_yearly_report_reminder_month';
  static const _kYearlyReportReminderDay = 'pref_yearly_report_reminder_day';
  static const _kYearlyReportReminderHour = 'pref_yearly_report_reminder_hour';
  static const _kYearlyReportReminderMinute =
      'pref_yearly_report_reminder_minute';
  static const _kBottomNavOrder = 'pref_bottom_nav_order';
  static const _kBottomNavVisible = 'pref_bottom_nav_visible';
  static const _kWebNavigationMigrated = 'pref_web_navigation_v2';
  static const _kFocusNavigationMigrated = 'pref_focus_navigation_v1';
  static const _kAppTimeZone = LocalTimezoneResolver.preferenceKey;
  static const _kAppTimeZoneMode = LocalTimezoneResolver.modePreferenceKey;
  static const _kTextScale = 'pref_text_scale';
  static const _kTextScaleOwner = 'pref_text_scale_owner_v1';

  Future<void> Function()? onAppTimeZoneChanged;

  /// 本地偏好写入后回调同步层。回调返回 Future 时会被 await，保证 setter
  /// 的 Future 完成前对应的同步 stamp / changedKeys 已落盘。
  FutureOr<void> Function(Iterable<String> keys)? onChangedKeys;

  int _firstDayOfWeek = 1; // 1=周一, 7=周日
  String _dateFormat = 'yyyy-MM-dd';
  int _defaultTab = 0; // 0=Today
  bool _haptic = true;
  bool _showLunar = true;
  // 本机首页布局偏好，与账号业务数据独立。
  bool _showHomeCalendar = false;
  bool _showCompletedTodos = false;
  // 应用内字号档位：只在本机生效，不进入账号业务数据。
  double _textScale = AppTextScale.defaultScale;
  // 当前字号归属的本机账号（服务器规范身份 + 用户ID）；null 表示尚未绑定。
  String? _textScaleOwner;
  // 字号相关写入的串行队列：换号重置必须排在旧的字号写入之后落盘。
  Future<void> _textScaleWriteQueue = Future<void>.value();
  int _defaultPomodoroMinutes = 25;
  bool _quickCaptureFab = true;
  bool _notificationQuickAdd = false;
  bool _notificationTodayProgress = false;
  int _notificationHistoryLimit = NotificationHistoryPolicy.defaultLimit;
  int _autoArchiveCompletedDays = 0; // 0=不归档
  bool _dailyReminderEnabled = false;
  ReminderKind _dailyReminderKind = ReminderKind.push;
  int _dailyReminderHour = 20;
  int _dailyReminderMinute = 0;
  bool _dailyReminderIncludeTodayTasks = true;
  bool _dailyReminderIncludeTomorrowPlan = true;
  bool _dailyReminderIncludeOverdue = true;
  List<int> _dailyReminderRepeatDays = const [1, 2, 3, 4, 5, 6, 7];
  bool _dailyReminderPauseHolidays = false;
  List<DailyReminderSlot> _dailyReminderSlots = const [
    DailyReminderSlot(),
    DailyReminderSlot(hour: 8, enabled: false),
    DailyReminderSlot(hour: 22, enabled: false),
  ];
  bool _dailyReportReminder = false;
  int _dailyReportReminderHour = 21;
  int _dailyReportReminderMinute = 30;
  bool _weeklyReportReminder = false;
  int _weeklyReportReminderWeekday = DateTime.monday;
  int _weeklyReportReminderHour = 9;
  int _weeklyReportReminderMinute = 0;
  bool _monthlyReportReminder = false;
  int _monthlyReportReminderDay = 1;
  int _monthlyReportReminderHour = 9;
  int _monthlyReportReminderMinute = 0;
  bool _yearlyReportReminder = false;
  int _yearlyReportReminderMonth = 1;
  int _yearlyReportReminderDay = 1;
  int _yearlyReportReminderHour = 9;
  int _yearlyReportReminderMinute = 0;
  List<int> _bottomNavOrder = const [0, 1, 2, 3, 4, 5, 6];
  Set<int> _bottomNavVisible = defaultBottomNavTabs;
  String _appTimeZone = LocalTimezoneResolver.defaultIana;
  bool _followSystemTimeZone = true;
  int _storageGeneration = 0;
  // 每次 setter 进入时递增：用于阻止载入期间读到的旧值覆盖用户新设置。
  int _mutationVersion = 0;
  // 所有进行中/已完成但未被载入等待过的偏好写入的汇合点。
  Future<void> _pendingPreferenceWrites = Future<void>.value();

  int get firstDayOfWeek => _firstDayOfWeek;
  String get dateFormat => _dateFormat;
  int get defaultTab => _defaultTab;
  bool get haptic => _haptic;
  bool get showLunar => _showLunar;
  bool get showHomeCalendar => _showHomeCalendar;
  bool get showCompletedTodos => _showCompletedTodos;
  double get textScale => _textScale;
  String? get textScaleOwner => _textScaleOwner;
  int get defaultPomodoroMinutes => _defaultPomodoroMinutes;
  bool get quickCaptureFab => _quickCaptureFab;
  bool get notificationQuickAdd => _notificationQuickAdd;
  bool get notificationTodayProgress => _notificationTodayProgress;
  int get notificationHistoryLimit => _notificationHistoryLimit;
  int get autoArchiveCompletedDays => _autoArchiveCompletedDays;
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get dailyReminderHour => _dailyReminderHour;
  int get dailyReminderMinute => _dailyReminderMinute;
  bool get dailyReminderIncludeTodayTasks => _dailyReminderIncludeTodayTasks;
  bool get dailyReminderIncludeTomorrowPlan =>
      _dailyReminderIncludeTomorrowPlan;
  bool get dailyReminderIncludeOverdue => _dailyReminderIncludeOverdue;
  List<int> get dailyReminderRepeatDays =>
      List.unmodifiable(_dailyReminderRepeatDays);
  bool get dailyReminderPauseHolidays => _dailyReminderPauseHolidays;
  List<DailyReminderSlot> get dailyReminderSlots =>
      List.unmodifiable(_dailyReminderSlots);
  bool get dailyReportReminder => _dailyReportReminder;
  int get dailyReportReminderHour => _dailyReportReminderHour;
  int get dailyReportReminderMinute => _dailyReportReminderMinute;
  ReportReminderConfig get dailyReportReminderConfig => ReportReminderConfig(
    enabled: _dailyReportReminder,
    hour: _dailyReportReminderHour,
    minute: _dailyReportReminderMinute,
  );
  bool get weeklyReportReminder => _weeklyReportReminder;
  int get weeklyReportReminderWeekday => _weeklyReportReminderWeekday;
  int get weeklyReportReminderHour => _weeklyReportReminderHour;
  int get weeklyReportReminderMinute => _weeklyReportReminderMinute;
  ReportReminderConfig get weeklyReportReminderConfig => ReportReminderConfig(
    enabled: _weeklyReportReminder,
    weekday: _weeklyReportReminderWeekday,
    hour: _weeklyReportReminderHour,
    minute: _weeklyReportReminderMinute,
  );
  bool get monthlyReportReminder => _monthlyReportReminder;
  int get monthlyReportReminderDay => _monthlyReportReminderDay;
  int get monthlyReportReminderHour => _monthlyReportReminderHour;
  int get monthlyReportReminderMinute => _monthlyReportReminderMinute;
  ReportReminderConfig get monthlyReportReminderConfig => ReportReminderConfig(
    enabled: _monthlyReportReminder,
    monthDay: _monthlyReportReminderDay,
    hour: _monthlyReportReminderHour,
    minute: _monthlyReportReminderMinute,
  );
  bool get yearlyReportReminder => _yearlyReportReminder;
  int get yearlyReportReminderMonth => _yearlyReportReminderMonth;
  int get yearlyReportReminderDay => _yearlyReportReminderDay;
  int get yearlyReportReminderHour => _yearlyReportReminderHour;
  int get yearlyReportReminderMinute => _yearlyReportReminderMinute;
  ReportReminderConfig get yearlyReportReminderConfig => ReportReminderConfig(
    enabled: _yearlyReportReminder,
    month: _yearlyReportReminderMonth,
    monthDay: _yearlyReportReminderDay,
    hour: _yearlyReportReminderHour,
    minute: _yearlyReportReminderMinute,
  );
  List<int> get bottomNavOrder => List.unmodifiable(_bottomNavOrder);
  Set<int> get bottomNavVisible => Set.unmodifiable(_bottomNavVisible);
  String get appTimeZone => _appTimeZone;
  bool get followSystemTimeZone => _followSystemTimeZone;
  String get appTimeZoneSelection => _followSystemTimeZone
      ? LocalTimezoneResolver.followSystemValue
      : _appTimeZone;
  List<int> get enabledBottomNavTabs => _bottomNavOrder
      .where((tab) => _bottomNavVisible.contains(tab))
      .toList(growable: false);
  List<int> get visibleBottomNavTabs => normalizedVisibleBottomNavTabs(
    order: _bottomNavOrder,
    visible: _bottomNavVisible,
  );

  static List<int> normalizedVisibleBottomNavTabs({
    required Iterable<int> order,
    required Iterable<int> visible,
  }) {
    final rawTabs = _normalizeNavOrder(
      order,
    ).where((tab) => visible.contains(tab)).toList(growable: false);
    if (rawTabs.isEmpty ||
        !rawTabs.any((tab) => !fixedBottomNavTabs.contains(tab))) {
      return List.unmodifiable(defaultBottomNavTabs);
    }

    final flexibleBudget = maxBottomNavTabs - fixedBottomNavTabs.length;
    final selected = <int>{};
    for (final tab in rawTabs) {
      if (fixedBottomNavTabs.contains(tab)) continue;
      if (selected.length >= flexibleBudget) break;
      selected.add(tab);
    }
    selected.addAll(fixedBottomNavTabs);

    final result = <int>[];
    for (final tab in rawTabs) {
      if (selected.contains(tab) && !result.contains(tab)) result.add(tab);
    }
    for (final tab in fixedBottomNavTabs) {
      if (!result.contains(tab)) result.add(tab);
    }
    while (result.length > maxBottomNavTabs) {
      final removeAt = result.indexWhere(
        (tab) => !fixedBottomNavTabs.contains(tab),
      );
      if (removeAt < 0) break;
      result.removeAt(removeAt);
    }
    return List.unmodifiable(result);
  }

  String formatDate(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    switch (_dateFormat) {
      case 'MM/dd/yyyy':
        return '$m/$dd/$y';
      case 'dd/MM/yyyy':
        return '$dd/$m/$y';
      case 'yyyy年M月d日':
        return '${d.year}年${d.month}月${d.day}日';
      case 'yyyy-MM-dd':
      default:
        return '$y-$m-$dd';
    }
  }

  void resetLocalState() {
    _storageGeneration++;
    _applyDefaults();
    notifyListeners();
  }

  void _applyDefaults() {
    _firstDayOfWeek = 1;
    _dateFormat = 'yyyy-MM-dd';
    _defaultTab = 0;
    _haptic = true;
    _showLunar = true;
    _showHomeCalendar = false;
    _showCompletedTodos = false;
    // 字号与归属账号是跨账号保留的本机偏好：账号清理/重载不回到标准档，
    // 是否重置由 bindTextScaleToAccount 判定；新建 provider 仍由字段默认值
    // 初始化为标准档。
    _defaultPomodoroMinutes = 25;
    _quickCaptureFab = true;
    _notificationQuickAdd = false;
    _notificationTodayProgress = false;
    _notificationHistoryLimit = NotificationHistoryPolicy.defaultLimit;
    _autoArchiveCompletedDays = 0;
    _dailyReminderEnabled = false;
    _dailyReminderKind = ReminderKind.push;
    _dailyReminderHour = 20;
    _dailyReminderMinute = 0;
    _dailyReminderIncludeTodayTasks = true;
    _dailyReminderIncludeTomorrowPlan = true;
    _dailyReminderIncludeOverdue = true;
    _dailyReminderRepeatDays = const [1, 2, 3, 4, 5, 6, 7];
    _dailyReminderPauseHolidays = false;
    _dailyReminderSlots = const [
      DailyReminderSlot(),
      DailyReminderSlot(hour: 8, enabled: false),
      DailyReminderSlot(hour: 22, enabled: false),
    ];
    _dailyReportReminder = false;
    _dailyReportReminderHour = 21;
    _dailyReportReminderMinute = 30;
    _weeklyReportReminder = false;
    _weeklyReportReminderWeekday = DateTime.monday;
    _weeklyReportReminderHour = 9;
    _weeklyReportReminderMinute = 0;
    _monthlyReportReminder = false;
    _monthlyReportReminderDay = 1;
    _monthlyReportReminderHour = 9;
    _monthlyReportReminderMinute = 0;
    _yearlyReportReminder = false;
    _yearlyReportReminderMonth = 1;
    _yearlyReportReminderDay = 1;
    _yearlyReportReminderHour = 9;
    _yearlyReportReminderMinute = 0;
    _bottomNavOrder = const [0, 1, 2, 3, 4, 5, 6];
    _bottomNavVisible = defaultBottomNavTabs;
    _followSystemTimeZone = true;
    _appTimeZone = LocalTimezoneResolver.currentIana;
  }

  /// 载入快照是否已过期：账号切换（generation）或载入期间有写入进入。
  bool _isStaleLoad(int generation, int mutationVersion) =>
      generation != _storageGeneration || mutationVersion != _mutationVersion;

  /// 包装一次偏好写入：进入时同步递增 [_mutationVersion] 并立即执行
  /// [operation]，保留 setter 在首个 await 前改写内存的时序；同时把本次
  /// 写入并入 [_pendingPreferenceWrites]，供载入流程等待其落盘。
  /// 返回原 Future 以保留调用方的错误传播；等待链自身消化错误，避免一次
  /// 失败永久阻塞后续载入。
  Future<void> _trackPreferenceWrite(Future<void> Function() operation) {
    _mutationVersion++;
    final result = Future<void>.sync(operation);
    final settled = Future.wait<void>([
      _pendingPreferenceWrites,
      result,
    ]).then<void>((_) {}, onError: (Object error, StackTrace stackTrace) {});
    _pendingPreferenceWrites = settled;
    return result;
  }

  /// 载入入口：先等待所有进行中的偏好写入落盘再读快照；若读的过程中又有
  /// 写入进入，等其结束并重新读取，直到内存与存储一致后才返回。
  /// 账号切换（generation 变化）时不重试，避免旧任务把数据写回新账号。
  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    while (true) {
      final pending = _pendingPreferenceWrites;
      await pending;
      if (generation != _storageGeneration) return;
      if (!identical(pending, _pendingPreferenceWrites)) continue;
      final mutationVersion = _mutationVersion;
      await _loadFromStorageSnapshot(generation, mutationVersion);
      if (generation != _storageGeneration) return;
      if (mutationVersion == _mutationVersion) return;
    }
  }

  Future<void> _loadFromStorageSnapshot(
    int generation,
    int mutationVersion,
  ) async {
    final p = await SharedPreferences.getInstance();
    if (_isStaleLoad(generation, mutationVersion)) return;
    _firstDayOfWeek = p.getInt(_kFirstDayOfWeek) ?? 1;
    _dateFormat = p.getString(_kDateFormat) ?? 'yyyy-MM-dd';
    _followSystemTimeZone =
        (p.getString(_kAppTimeZoneMode) ??
            LocalTimezoneResolver.followSystemValue) !=
        LocalTimezoneResolver.fixedValue;
    await LocalTimezoneResolver.setApplicationTimeZone(
      _followSystemTimeZone
          ? LocalTimezoneResolver.followSystemValue
          : (p.getString(_kAppTimeZone) ?? LocalTimezoneResolver.defaultIana),
    );
    if (_isStaleLoad(generation, mutationVersion)) return;
    _appTimeZone = LocalTimezoneResolver.currentIana;
    final storedOrder = p.getStringList(_kBottomNavOrder);
    final storedVisible = p.getStringList(_kBottomNavVisible);
    final needsWebNavMigration =
        WebTarget.isWebBuild && !(p.getBool(_kWebNavigationMigrated) ?? false);
    final storedVisibleSet = storedVisible
        ?.map(int.tryParse)
        .whereType<int>()
        .toSet();
    final legacyWebDefault =
        needsWebNavMigration &&
        (setEquals(storedVisibleSet, const <int>{0, 1, 2, 5, 6}) ||
            setEquals(storedVisibleSet, const <int>{0, 1, 2, 3, 6}));
    final needsFocusNavMigration =
        !(p.getBool(_kFocusNavigationMigrated) ?? false);
    // 只升级旧默认入口；保留自定义顺序，且不覆盖迁移后主动隐藏专注的选择。
    final legacyFocusDefault =
        needsFocusNavMigration &&
        (setEquals(storedVisibleSet, const <int>{0, 1, 2, 6}) ||
            setEquals(storedVisibleSet, const <int>{0, 1, 2, 5, 6}));
    final isOldBottomNavConfig =
        (storedOrder == null || !storedOrder.contains('6')) &&
        (storedVisible == null || !storedVisible.contains('6'));
    final storedDefaultTab = p.getInt(_kDefaultTab) ?? 0;
    _defaultTab = normalizeDefaultTab(
      isOldBottomNavConfig && storedDefaultTab == 5 ? 6 : storedDefaultTab,
    );
    _haptic = p.getBool(_kHapticFeedback) ?? true;
    _showLunar = p.getBool(_kShowLunar) ?? true;
    _showHomeCalendar = p.getBool(_kShowHomeCalendar) ?? false;
    _showCompletedTodos = p.getBool(_kShowCompletedTodos) ?? false;
    _textScale = AppTextScale.normalize(p.getDouble(_kTextScale));
    final storedTextScaleOwner = p.getString(_kTextScaleOwner)?.trim();
    _textScaleOwner =
        storedTextScaleOwner == null || storedTextScaleOwner.isEmpty
        ? null
        : storedTextScaleOwner;
    _defaultPomodoroMinutes = p.getInt(_kDefaultPomodoroMinutes) ?? 25;
    _quickCaptureFab = p.getBool(_kQuickCaptureFab) ?? true;
    _notificationQuickAdd = p.getBool(_kNotificationQuickAdd) ?? false;
    _notificationTodayProgress =
        p.getBool(_kNotificationTodayProgress) ?? false;
    _notificationHistoryLimit = NotificationHistoryPolicy.normalize(
      p.getInt(_kNotificationHistoryLimit),
    );
    _autoArchiveCompletedDays = p.getInt(_kAutoArchiveCompletedDays) ?? 0;
    _dailyReminderEnabled = p.getBool(_kDailyReminderEnabled) ?? false;
    _dailyReminderKind = DailyReminderSlot.parseKind(
      p.getString(_kDailyReminderKind),
    );
    if (_dailyReminderKind == ReminderKind.off) {
      _dailyReminderEnabled = false;
    }
    _dailyReminderHour = p.getInt(_kDailyReminderHour) ?? 20;
    _dailyReminderMinute = p.getInt(_kDailyReminderMinute) ?? 0;
    _dailyReminderIncludeTodayTasks =
        p.getBool(_kDailyReminderIncludeTodayTasks) ?? true;
    _dailyReminderIncludeTomorrowPlan =
        p.getBool(_kDailyReminderIncludeTomorrowPlan) ?? true;
    _dailyReminderIncludeOverdue =
        p.getBool(_kDailyReminderIncludeOverdue) ?? true;
    _dailyReminderRepeatDays =
        p
            .getStringList(_kDailyReminderRepeatDays)
            ?.map(int.tryParse)
            .whereType<int>()
            .where((d) => d >= 1 && d <= 7)
            .toList() ??
        const [1, 2, 3, 4, 5, 6, 7];
    if (_dailyReminderRepeatDays.isEmpty) {
      _dailyReminderRepeatDays = const [1, 2, 3, 4, 5, 6, 7];
    }
    _dailyReminderPauseHolidays =
        p.getBool(_kDailyReminderPauseHolidays) ?? false;
    _dailyReminderSlots = List.generate(3, (i) {
      if (i == 0) {
        return DailyReminderSlot(
          enabled: _dailyReminderEnabled,
          kind: _dailyReminderKind,
          hour: _dailyReminderHour,
          minute: _dailyReminderMinute,
          includeTodayTasks: _dailyReminderIncludeTodayTasks,
          includeTomorrowPlan: _dailyReminderIncludeTomorrowPlan,
          includeOverdue: _dailyReminderIncludeOverdue,
          repeatDays: _dailyReminderRepeatDays,
          pauseHolidays: _dailyReminderPauseHolidays,
        );
      }
      final prefix = '$_kDailyReminderSlotPrefix${i + 1}';
      final kind = DailyReminderSlot.parseKind(p.getString('${prefix}_kind'));
      return DailyReminderSlot(
        enabled:
            kind != ReminderKind.off &&
            (p.getBool('${prefix}_enabled') ?? false),
        kind: kind,
        hour: p.getInt('${prefix}_hour') ?? (i == 1 ? 8 : 22),
        minute: p.getInt('${prefix}_minute') ?? 0,
        includeTodayTasks: p.getBool('${prefix}_today') ?? true,
        includeTomorrowPlan: p.getBool('${prefix}_tomorrow') ?? true,
        includeOverdue: p.getBool('${prefix}_overdue') ?? true,
        repeatDays: DailyReminderSlot._normalizeDays(
          p
                  .getStringList('${prefix}_repeat_days')
                  ?.map(int.tryParse)
                  .whereType<int>()
                  .toList() ??
              const [1, 2, 3, 4, 5, 6, 7],
        ),
        pauseHolidays: p.getBool('${prefix}_pause_holidays') ?? false,
      );
    });
    _dailyReportReminder = p.getBool(_kDailyReportReminder) ?? false;
    _dailyReportReminderHour = (p.getInt(_kDailyReportReminderHour) ?? 21)
        .clamp(0, 23);
    _dailyReportReminderMinute = (p.getInt(_kDailyReportReminderMinute) ?? 30)
        .clamp(0, 59);
    _weeklyReportReminder = p.getBool(_kWeeklyReportReminder) ?? false;
    _weeklyReportReminderWeekday =
        (p.getInt(_kWeeklyReportReminderWeekday) ?? DateTime.monday).clamp(
          1,
          7,
        );
    _weeklyReportReminderHour = (p.getInt(_kWeeklyReportReminderHour) ?? 9)
        .clamp(0, 23);
    _weeklyReportReminderMinute = (p.getInt(_kWeeklyReportReminderMinute) ?? 0)
        .clamp(0, 59);
    _monthlyReportReminder = p.getBool(_kMonthlyReportReminder) ?? false;
    _monthlyReportReminderDay = (p.getInt(_kMonthlyReportReminderDay) ?? 1)
        .clamp(1, 31);
    _monthlyReportReminderHour = (p.getInt(_kMonthlyReportReminderHour) ?? 9)
        .clamp(0, 23);
    _monthlyReportReminderMinute =
        (p.getInt(_kMonthlyReportReminderMinute) ?? 0).clamp(0, 59);
    _yearlyReportReminder = p.getBool(_kYearlyReportReminder) ?? false;
    _yearlyReportReminderMonth = (p.getInt(_kYearlyReportReminderMonth) ?? 1)
        .clamp(1, 12);
    _yearlyReportReminderDay = (p.getInt(_kYearlyReportReminderDay) ?? 1).clamp(
      1,
      31,
    );
    _yearlyReportReminderHour = (p.getInt(_kYearlyReportReminderHour) ?? 9)
        .clamp(0, 23);
    _yearlyReportReminderMinute = (p.getInt(_kYearlyReportReminderMinute) ?? 0)
        .clamp(0, 59);
    _bottomNavOrder = _normalizeNavOrder(
      storedOrder?.map(int.tryParse).whereType<int>(),
    );
    _bottomNavVisible = _normalizeNavVisible(
      legacyWebDefault || legacyFocusDefault
          ? defaultBottomNavTabs
          : storedVisible?.map(int.tryParse).whereType<int>(),
      order: _bottomNavOrder,
    );
    if (_isStaleLoad(generation, mutationVersion)) return;
    if ((WebTarget.isWebBuild || legacyFocusDefault) &&
        storedVisible != null &&
        !setEquals(storedVisibleSet, _bottomNavVisible)) {
      await p.setStringList(
        _kBottomNavVisible,
        _bottomNavVisible.map((tab) => '$tab').toList(),
      );
      if (_isStaleLoad(generation, mutationVersion)) return;
    }
    if (needsWebNavMigration) {
      await p.setBool(_kWebNavigationMigrated, true);
      if (_isStaleLoad(generation, mutationVersion)) return;
    }
    if (needsFocusNavMigration) {
      await p.setBool(_kFocusNavigationMigrated, true);
      if (_isStaleLoad(generation, mutationVersion)) return;
    }
    notifyListeners();
  }

  /// 先刷新 UI，再等待同步回调（stamp / changedKeys / pending 持久化）。
  /// 这样 setter 的 Future 完成时配置与同步元数据都已落盘。
  Future<void> _notifyPreferenceKeys(Iterable<String> keys) async {
    final cleanKeys = keys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet();
    notifyListeners();
    if (cleanKeys.isEmpty) return;
    final callback = onChangedKeys;
    if (callback == null) return;
    await callback(cleanKeys);
  }

  List<String> _dailyReminderSlotKeys(int index) {
    if (index == 0) {
      return const [
        _kDailyReminderEnabled,
        _kDailyReminderKind,
        _kDailyReminderHour,
        _kDailyReminderMinute,
        _kDailyReminderIncludeTodayTasks,
        _kDailyReminderIncludeTomorrowPlan,
        _kDailyReminderIncludeOverdue,
        _kDailyReminderRepeatDays,
        _kDailyReminderPauseHolidays,
      ];
    }
    final prefix = '$_kDailyReminderSlotPrefix${index + 1}';
    return [
      '${prefix}_enabled',
      '${prefix}_kind',
      '${prefix}_hour',
      '${prefix}_minute',
      '${prefix}_today',
      '${prefix}_tomorrow',
      '${prefix}_overdue',
      '${prefix}_repeat_days',
      '${prefix}_pause_holidays',
    ];
  }

  Future<void> setFirstDayOfWeek(int value) => _trackPreferenceWrite(() async {
    _firstDayOfWeek = value.clamp(1, 7);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kFirstDayOfWeek, _firstDayOfWeek);
    await _notifyPreferenceKeys(const [_kFirstDayOfWeek]);
  });

  void refreshResolvedTimeZone() {
    final resolved = LocalTimezoneResolver.currentIana;
    if (_appTimeZone == resolved) return;
    _appTimeZone = resolved;
    notifyListeners();
  }

  Future<void> setAppTimeZone(String value) => _trackPreferenceWrite(() async {
    final next = value == LocalTimezoneResolver.followSystemValue
        ? LocalTimezoneResolver.followSystemValue
        : value.isEmpty
        ? LocalTimezoneResolver.defaultIana
        : value;
    _followSystemTimeZone = next == LocalTimezoneResolver.followSystemValue;
    await LocalTimezoneResolver.setApplicationTimeZone(next);
    _appTimeZone = LocalTimezoneResolver.currentIana;
    await _notifyPreferenceKeys(const [_kAppTimeZoneMode, _kAppTimeZone]);
    await onAppTimeZoneChanged?.call();
  });

  Future<void> setDailyReminderSlot(
    int index,
    DailyReminderSlot slot,
  ) => _trackPreferenceWrite(() async {
    if (index < 0 || index >= 3) return;
    final normalizedSlot = slot.copyWith();
    if (_sameDailyReminderSlot(_dailyReminderSlots[index], normalizedSlot)) {
      return;
    }
    final next = [..._dailyReminderSlots];
    next[index] = normalizedSlot;
    _dailyReminderSlots = List.unmodifiable(next);

    if (index == 0) {
      _dailyReminderEnabled = normalizedSlot.enabled;
      _dailyReminderKind = normalizedSlot.kind;
      _dailyReminderHour = normalizedSlot.hour;
      _dailyReminderMinute = normalizedSlot.minute;
      _dailyReminderIncludeTodayTasks = normalizedSlot.includeTodayTasks;
      _dailyReminderIncludeTomorrowPlan = normalizedSlot.includeTomorrowPlan;
      _dailyReminderIncludeOverdue = normalizedSlot.includeOverdue;
      _dailyReminderRepeatDays = DailyReminderSlot._normalizeDays(
        normalizedSlot.repeatDays,
      );
      _dailyReminderPauseHolidays = normalizedSlot.pauseHolidays;
    }

    final p = await SharedPreferences.getInstance();
    final prefix = index == 0 ? null : '$_kDailyReminderSlotPrefix${index + 1}';
    if (index == 0) {
      await p.setBool(_kDailyReminderEnabled, normalizedSlot.enabled);
      await p.setString(_kDailyReminderKind, normalizedSlot.kind.name);
      await p.setInt(_kDailyReminderHour, normalizedSlot.hour);
      await p.setInt(_kDailyReminderMinute, normalizedSlot.minute);
      await p.setBool(
        _kDailyReminderIncludeTodayTasks,
        normalizedSlot.includeTodayTasks,
      );
      await p.setBool(
        _kDailyReminderIncludeTomorrowPlan,
        normalizedSlot.includeTomorrowPlan,
      );
      await p.setBool(
        _kDailyReminderIncludeOverdue,
        normalizedSlot.includeOverdue,
      );
      await p.setStringList(
        _kDailyReminderRepeatDays,
        DailyReminderSlot._normalizeDays(
          normalizedSlot.repeatDays,
        ).map((d) => d.toString()).toList(),
      );
      await p.setBool(
        _kDailyReminderPauseHolidays,
        normalizedSlot.pauseHolidays,
      );
    } else {
      await p.setBool('${prefix}_enabled', normalizedSlot.enabled);
      await p.setString('${prefix}_kind', normalizedSlot.kind.name);
      await p.setInt('${prefix}_hour', normalizedSlot.hour);
      await p.setInt('${prefix}_minute', normalizedSlot.minute);
      await p.setBool('${prefix}_today', normalizedSlot.includeTodayTasks);
      await p.setBool('${prefix}_tomorrow', normalizedSlot.includeTomorrowPlan);
      await p.setBool('${prefix}_overdue', normalizedSlot.includeOverdue);
      await p.setStringList(
        '${prefix}_repeat_days',
        DailyReminderSlot._normalizeDays(
          normalizedSlot.repeatDays,
        ).map((d) => d.toString()).toList(),
      );
      await p.setBool('${prefix}_pause_holidays', normalizedSlot.pauseHolidays);
    }
    await _notifyPreferenceKeys(_dailyReminderSlotKeys(index));
  });

  Future<void> setWeeklyReportReminder(bool value) =>
      _trackPreferenceWrite(() async {
        _weeklyReportReminder = value;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kWeeklyReportReminder, value);
        await _notifyPreferenceKeys(const [_kWeeklyReportReminder]);
      });

  Future<void> setDailyReportReminder(bool value) =>
      _trackPreferenceWrite(() async {
        _dailyReportReminder = value;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kDailyReportReminder, value);
        await _notifyPreferenceKeys(const [_kDailyReportReminder]);
      });

  Future<void> setDailyReportReminderConfig(ReportReminderConfig config) =>
      _trackPreferenceWrite(() async {
        final nextEnabled = config.enabled;
        final nextHour = config.hour.clamp(0, 23);
        final nextMinute = config.minute.clamp(0, 59);
        if (_dailyReportReminder == nextEnabled &&
            _dailyReportReminderHour == nextHour &&
            _dailyReportReminderMinute == nextMinute) {
          return;
        }
        _dailyReportReminder = nextEnabled;
        _dailyReportReminderHour = nextHour;
        _dailyReportReminderMinute = nextMinute;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kDailyReportReminder, _dailyReportReminder);
        await p.setInt(_kDailyReportReminderHour, _dailyReportReminderHour);
        await p.setInt(_kDailyReportReminderMinute, _dailyReportReminderMinute);
        await _notifyPreferenceKeys(const [
          _kDailyReportReminder,
          _kDailyReportReminderHour,
          _kDailyReportReminderMinute,
        ]);
      });

  Future<void> setWeeklyReportReminderConfig(
    ReportReminderConfig config,
  ) => _trackPreferenceWrite(() async {
    final nextEnabled = config.enabled;
    final nextWeekday = config.weekday.clamp(1, 7);
    final nextHour = config.hour.clamp(0, 23);
    final nextMinute = config.minute.clamp(0, 59);
    if (_weeklyReportReminder == nextEnabled &&
        _weeklyReportReminderWeekday == nextWeekday &&
        _weeklyReportReminderHour == nextHour &&
        _weeklyReportReminderMinute == nextMinute) {
      return;
    }
    _weeklyReportReminder = nextEnabled;
    _weeklyReportReminderWeekday = nextWeekday;
    _weeklyReportReminderHour = nextHour;
    _weeklyReportReminderMinute = nextMinute;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWeeklyReportReminder, _weeklyReportReminder);
    await p.setInt(_kWeeklyReportReminderWeekday, _weeklyReportReminderWeekday);
    await p.setInt(_kWeeklyReportReminderHour, _weeklyReportReminderHour);
    await p.setInt(_kWeeklyReportReminderMinute, _weeklyReportReminderMinute);
    await _notifyPreferenceKeys(const [
      _kWeeklyReportReminder,
      _kWeeklyReportReminderWeekday,
      _kWeeklyReportReminderHour,
      _kWeeklyReportReminderMinute,
    ]);
  });

  Future<void> setMonthlyReportReminder(bool value) =>
      _trackPreferenceWrite(() async {
        _monthlyReportReminder = value;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kMonthlyReportReminder, value);
        await _notifyPreferenceKeys(const [_kMonthlyReportReminder]);
      });

  Future<void> setMonthlyReportReminderConfig(ReportReminderConfig config) =>
      _trackPreferenceWrite(() async {
        final nextEnabled = config.enabled;
        final nextDay = config.monthDay.clamp(1, 31);
        final nextHour = config.hour.clamp(0, 23);
        final nextMinute = config.minute.clamp(0, 59);
        if (_monthlyReportReminder == nextEnabled &&
            _monthlyReportReminderDay == nextDay &&
            _monthlyReportReminderHour == nextHour &&
            _monthlyReportReminderMinute == nextMinute) {
          return;
        }
        _monthlyReportReminder = nextEnabled;
        _monthlyReportReminderDay = nextDay;
        _monthlyReportReminderHour = nextHour;
        _monthlyReportReminderMinute = nextMinute;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kMonthlyReportReminder, _monthlyReportReminder);
        await p.setInt(_kMonthlyReportReminderDay, _monthlyReportReminderDay);
        await p.setInt(_kMonthlyReportReminderHour, _monthlyReportReminderHour);
        await p.setInt(
          _kMonthlyReportReminderMinute,
          _monthlyReportReminderMinute,
        );
        await _notifyPreferenceKeys(const [
          _kMonthlyReportReminder,
          _kMonthlyReportReminderDay,
          _kMonthlyReportReminderHour,
          _kMonthlyReportReminderMinute,
        ]);
      });

  Future<void> setYearlyReportReminder(bool value) =>
      _trackPreferenceWrite(() async {
        _yearlyReportReminder = value;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kYearlyReportReminder, value);
        await _notifyPreferenceKeys(const [_kYearlyReportReminder]);
      });

  Future<void> setYearlyReportReminderConfig(ReportReminderConfig config) =>
      _trackPreferenceWrite(() async {
        final nextEnabled = config.enabled;
        final nextMonth = config.month.clamp(1, 12);
        final nextDay = config.monthDay.clamp(1, 31);
        final nextHour = config.hour.clamp(0, 23);
        final nextMinute = config.minute.clamp(0, 59);
        if (_yearlyReportReminder == nextEnabled &&
            _yearlyReportReminderMonth == nextMonth &&
            _yearlyReportReminderDay == nextDay &&
            _yearlyReportReminderHour == nextHour &&
            _yearlyReportReminderMinute == nextMinute) {
          return;
        }
        _yearlyReportReminder = nextEnabled;
        _yearlyReportReminderMonth = nextMonth;
        _yearlyReportReminderDay = nextDay;
        _yearlyReportReminderHour = nextHour;
        _yearlyReportReminderMinute = nextMinute;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kYearlyReportReminder, _yearlyReportReminder);
        await p.setInt(_kYearlyReportReminderMonth, _yearlyReportReminderMonth);
        await p.setInt(_kYearlyReportReminderDay, _yearlyReportReminderDay);
        await p.setInt(_kYearlyReportReminderHour, _yearlyReportReminderHour);
        await p.setInt(
          _kYearlyReportReminderMinute,
          _yearlyReportReminderMinute,
        );
        await _notifyPreferenceKeys(const [
          _kYearlyReportReminder,
          _kYearlyReportReminderMonth,
          _kYearlyReportReminderDay,
          _kYearlyReportReminderHour,
          _kYearlyReportReminderMinute,
        ]);
      });

  Future<void> setBottomNavVisible(int tab, bool visible) =>
      _trackPreferenceWrite(() async {
        if (tab < 0 || tab > 6) return;
        if (!isBottomNavTabSupported(tab)) return;
        if (fixedBottomNavTabs.contains(tab) && !visible) return;
        if (visible &&
            !_bottomNavVisible.contains(tab) &&
            _bottomNavVisible.length >= maxBottomNavTabs) {
          return;
        }
        final next = {..._bottomNavVisible};
        if (visible) {
          next.add(tab);
        } else if (next.length > 2) {
          next.remove(tab);
        }
        _bottomNavVisible = _normalizeNavVisible(next, order: _bottomNavOrder);
        final p = await SharedPreferences.getInstance();
        await p.setStringList(
          _kBottomNavVisible,
          _bottomNavVisible.map((v) => v.toString()).toList(),
        );
        await _notifyPreferenceKeys(const [_kBottomNavVisible]);
      });

  Future<void> moveBottomNavTab(int tab, int delta) =>
      _trackPreferenceWrite(() async {
        final list = [..._bottomNavOrder];
        final index = list.indexOf(tab);
        if (index < 0) return;
        final nextIndex = (index + delta).clamp(0, list.length - 1);
        if (nextIndex == index) return;
        list.removeAt(index);
        list.insert(nextIndex, tab);
        _bottomNavOrder = _normalizeNavOrder(list);
        final p = await SharedPreferences.getInstance();
        await p.setStringList(
          _kBottomNavOrder,
          _bottomNavOrder.map((v) => v.toString()).toList(),
        );
        await _notifyPreferenceKeys(const [_kBottomNavOrder]);
      });

  static List<int> _normalizeNavOrder(Iterable<int>? source) {
    final result = <int>[];
    for (final tab in source ?? const <int>[]) {
      if (tab >= 0 &&
          tab <= 6 &&
          isBottomNavTabSupported(tab) &&
          !result.contains(tab)) {
        result.add(tab);
      }
    }
    for (var i = 0; i < 7; i++) {
      if (isBottomNavTabSupported(i) && !result.contains(i)) result.add(i);
    }
    return List.unmodifiable(result);
  }

  static Set<int> _normalizeNavVisible(
    Iterable<int>? source, {
    Iterable<int>? order,
  }) {
    final orderList = _normalizeNavOrder(order);
    final result = <int>{};
    for (final tab in source ?? const <int>[]) {
      if (tab >= 0 && tab <= 6 && isBottomNavTabSupported(tab)) {
        result.add(tab);
      }
    }
    if (source == null) {
      result.addAll(defaultBottomNavTabs);
    } else if (!result.any((tab) => !fixedBottomNavTabs.contains(tab))) {
      result.addAll(orderList);
    }
    result.addAll(fixedBottomNavTabs);

    final visible = <int>{};
    for (final tab in orderList) {
      if (fixedBottomNavTabs.contains(tab) || !result.contains(tab)) continue;
      if (visible.length >= maxBottomNavTabs - fixedBottomNavTabs.length) {
        break;
      }
      visible.add(tab);
    }
    visible.addAll(fixedBottomNavTabs);
    return Set.unmodifiable(visible);
  }

  Future<void> setDateFormat(String format) => _trackPreferenceWrite(() async {
    _dateFormat = format;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDateFormat, format);
    await _notifyPreferenceKeys(const [_kDateFormat]);
  });

  Future<void> setDefaultTab(int tab) => _trackPreferenceWrite(() async {
    final normalized = normalizeDefaultTab(tab);
    _defaultTab = normalized;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kDefaultTab, normalized);
    await _notifyPreferenceKeys(const [_kDefaultTab]);
  });

  Future<void> setHaptic(bool value) => _trackPreferenceWrite(() async {
    _haptic = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHapticFeedback, value);
    await _notifyPreferenceKeys(const [_kHapticFeedback]);
  });

  Future<void> setShowLunar(bool value) => _trackPreferenceWrite(() async {
    _showLunar = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowLunar, value);
    await _notifyPreferenceKeys(const [_kShowLunar]);
  });

  Future<void> setShowHomeCalendar(bool value) =>
      _trackPreferenceWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setBool(_kShowHomeCalendar, value)) return;
        _showHomeCalendar = value;
        notifyListeners();
      });

  Future<void> setShowCompletedTodos(bool value) =>
      _trackPreferenceWrite(() async {
        _showCompletedTodos = value;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kShowCompletedTodos, value);
        await _notifyPreferenceKeys(const [_kShowCompletedTodos]);
      });

  /// 字号写入串行化：调用顺序即落盘顺序，换号重置不会被旧写入覆盖。
  Future<void> _queueTextScaleWrite(Future<void> Function() operation) {
    final queued = _textScaleWriteQueue
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .then<void>((_) => operation());
    _textScaleWriteQueue = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return _trackPreferenceWrite(() => queued);
  }

  /// 只接受 [AppTextScale.options] 中的档位，其他输入归一化后保存。
  Future<void> setTextScale(double value) {
    final next = AppTextScale.normalize(value);
    final ownerAtRequest = _textScaleOwner;
    return _queueTextScaleWrite(() async {
      if (_textScaleOwner != ownerAtRequest) {
        throw StateError('Text scale account changed before saving');
      }
      final p = await SharedPreferences.getInstance();
      try {
        if (!await p.setDouble(_kTextScale, next)) {
          throw StateError('Unable to persist text scale');
        }
      } catch (_) {
        // Legacy SharedPreferences changes its cache before the platform write.
        // Re-read the stored snapshot so a failed draft cannot reappear on load.
        await p.reload();
        rethrow;
      }
      _textScale = next;
      notifyListeners();
    });
  }

  /// 把本机字号绑定到当前账号（服务器规范身份 + 用户ID）。
  ///
  /// - 空 [userId] 不绑定，也不清除已有归属；
  /// - 首次绑定（无旧 owner）保留当前已保存字号；
  /// - 同一账号不重置；
  /// - 不同已知账号把字号恢复标准档并记录新 owner。
  Future<void> bindTextScaleToAccount({
    required String serverUrl,
    required String? userId,
  }) {
    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      return Future<void>.value();
    }
    final owner = jsonEncode([
      ServerConnection.identity(serverUrl),
      normalizedUserId,
    ]);
    return _queueTextScaleWrite(() async {
      final p = await SharedPreferences.getInstance();
      final storedOwner = p.getString(_kTextScaleOwner)?.trim();
      final previousOwner =
          _textScaleOwner ??
          (storedOwner == null || storedOwner.isEmpty ? null : storedOwner);
      if (previousOwner == owner && _textScaleOwner == owner) return;
      final nextScale = previousOwner == null || previousOwner == owner
          ? AppTextScale.normalize(p.getDouble(_kTextScale) ?? _textScale)
          : AppTextScale.defaultScale;
      try {
        if (!await p.setDouble(_kTextScale, nextScale) ||
            !await p.setString(_kTextScaleOwner, owner)) {
          throw StateError('Unable to persist text scale account');
        }
      } catch (_) {
        await p.reload();
        rethrow;
      }
      _textScale = nextScale;
      _textScaleOwner = owner;
      notifyListeners();
    });
  }

  Future<void> setDefaultPomodoroMinutes(int value) =>
      _trackPreferenceWrite(() async {
        _defaultPomodoroMinutes = value.clamp(5, 180);
        final p = await SharedPreferences.getInstance();
        await p.setInt(_kDefaultPomodoroMinutes, _defaultPomodoroMinutes);
        await _notifyPreferenceKeys(const [_kDefaultPomodoroMinutes]);
      });

  Future<void> setQuickCaptureFab(bool value) =>
      _trackPreferenceWrite(() async {
        _quickCaptureFab = value;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kQuickCaptureFab, value);
        await _notifyPreferenceKeys(const [_kQuickCaptureFab]);
      });

  Future<void> setNotificationQuickAdd(bool value) =>
      _trackPreferenceWrite(() async {
        _notificationQuickAdd = value;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kNotificationQuickAdd, value);
        await _notifyPreferenceKeys(const [_kNotificationQuickAdd]);
      });

  Future<void> setNotificationTodayProgress(bool value) =>
      _trackPreferenceWrite(() async {
        _notificationTodayProgress = value;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kNotificationTodayProgress, value);
        await _notifyPreferenceKeys(const [_kNotificationTodayProgress]);
      });

  Future<void> setNotificationHistoryLimit(int value) =>
      _trackPreferenceWrite(() async {
        _notificationHistoryLimit = NotificationHistoryPolicy.normalize(value);
        final p = await SharedPreferences.getInstance();
        await p.setInt(_kNotificationHistoryLimit, _notificationHistoryLimit);
        await _notifyPreferenceKeys(const [_kNotificationHistoryLimit]);
      });

  Future<void> setAutoArchiveCompletedDays(int days) =>
      _trackPreferenceWrite(() async {
        _autoArchiveCompletedDays = days.clamp(0, 365);
        final p = await SharedPreferences.getInstance();
        await p.setInt(_kAutoArchiveCompletedDays, _autoArchiveCompletedDays);
        await _notifyPreferenceKeys(const [_kAutoArchiveCompletedDays]);
      });

  Future<void> setDailyReminderEnabled(bool value) =>
      _trackPreferenceWrite(() async {
        final currentSlot = _dailyReminderSlots[0];
        final nextSlot = value && currentSlot.kind == ReminderKind.off
            ? currentSlot.copyWith(enabled: true, kind: ReminderKind.push)
            : currentSlot.copyWith(enabled: value);
        _dailyReminderEnabled = nextSlot.enabled;
        _dailyReminderKind = nextSlot.kind;
        _dailyReminderSlots = _replaceSlot(0, nextSlot);

        final changedKeys = <String>[_kDailyReminderEnabled];
        if (nextSlot.kind != currentSlot.kind) {
          changedKeys.add(_kDailyReminderKind);
        }

        final p = await SharedPreferences.getInstance();
        await p.setBool(_kDailyReminderEnabled, nextSlot.enabled);
        if (nextSlot.kind != currentSlot.kind) {
          await p.setString(_kDailyReminderKind, nextSlot.kind.name);
        }
        await _notifyPreferenceKeys(changedKeys);
      });

  Future<void> setDailyReminderTime(int hour, int minute) =>
      _trackPreferenceWrite(() async {
        _dailyReminderHour = hour.clamp(0, 23);
        _dailyReminderMinute = minute.clamp(0, 59);
        _dailyReminderSlots = _replaceSlot(
          0,
          _dailyReminderSlots[0].copyWith(
            hour: _dailyReminderHour,
            minute: _dailyReminderMinute,
          ),
        );
        final p = await SharedPreferences.getInstance();
        await p.setInt(_kDailyReminderHour, _dailyReminderHour);
        await p.setInt(_kDailyReminderMinute, _dailyReminderMinute);
        await _notifyPreferenceKeys(const [
          _kDailyReminderHour,
          _kDailyReminderMinute,
        ]);
      });

  Future<void> setDailyReminderIncludeTodayTasks(bool value) =>
      _trackPreferenceWrite(() async {
        _dailyReminderIncludeTodayTasks = value;
        _dailyReminderSlots = _replaceSlot(
          0,
          _dailyReminderSlots[0].copyWith(includeTodayTasks: value),
        );
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kDailyReminderIncludeTodayTasks, value);
        await _notifyPreferenceKeys(const [_kDailyReminderIncludeTodayTasks]);
      });

  Future<void> setDailyReminderIncludeTomorrowPlan(bool value) =>
      _trackPreferenceWrite(() async {
        _dailyReminderIncludeTomorrowPlan = value;
        _dailyReminderSlots = _replaceSlot(
          0,
          _dailyReminderSlots[0].copyWith(includeTomorrowPlan: value),
        );
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kDailyReminderIncludeTomorrowPlan, value);
        await _notifyPreferenceKeys(const [_kDailyReminderIncludeTomorrowPlan]);
      });

  Future<void> setDailyReminderIncludeOverdue(bool value) =>
      _trackPreferenceWrite(() async {
        _dailyReminderIncludeOverdue = value;
        _dailyReminderSlots = _replaceSlot(
          0,
          _dailyReminderSlots[0].copyWith(includeOverdue: value),
        );
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kDailyReminderIncludeOverdue, value);
        await _notifyPreferenceKeys(const [_kDailyReminderIncludeOverdue]);
      });

  Future<void> setDailyReminderRepeatDays(List<int> days) =>
      _trackPreferenceWrite(() async {
        final normalized = days.where((d) => d >= 1 && d <= 7).toSet().toList()
          ..sort();
        _dailyReminderRepeatDays = normalized.isEmpty
            ? const [1, 2, 3, 4, 5, 6, 7]
            : normalized;
        _dailyReminderSlots = _replaceSlot(
          0,
          _dailyReminderSlots[0].copyWith(repeatDays: _dailyReminderRepeatDays),
        );
        final p = await SharedPreferences.getInstance();
        await p.setStringList(
          _kDailyReminderRepeatDays,
          _dailyReminderRepeatDays.map((d) => d.toString()).toList(),
        );
        await _notifyPreferenceKeys(const [_kDailyReminderRepeatDays]);
      });

  Future<void> setDailyReminderPauseHolidays(bool value) =>
      _trackPreferenceWrite(() async {
        _dailyReminderPauseHolidays = value;
        _dailyReminderSlots = _replaceSlot(
          0,
          _dailyReminderSlots[0].copyWith(pauseHolidays: value),
        );
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kDailyReminderPauseHolidays, value);
        await _notifyPreferenceKeys(const [_kDailyReminderPauseHolidays]);
      });

  List<DailyReminderSlot> _replaceSlot(int index, DailyReminderSlot slot) {
    final next = [..._dailyReminderSlots];
    next[index] = slot;
    return List.unmodifiable(next);
  }
}
