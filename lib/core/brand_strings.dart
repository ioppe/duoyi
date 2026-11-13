import 'app_brand.dart';
import 'brand_strings_en/botw.dart';
import 'brand_strings_en/default_brand.dart';
import 'brand_strings_en/genshin.dart';
import 'brand_strings_en/liquid_glass.dart';
import 'brand_strings_en/re0.dart';
import 'brand_strings_en/star_rail.dart';
import 'brand_strings_en/wuthering.dart';
import 'brand_strings_en/yanyun.dart';
import 'brand_strings_en/zzz.dart';
import 'i18n.dart';

export 'brand_strings_en/botw.dart';
export 'brand_strings_en/default_brand.dart';
export 'brand_strings_en/genshin.dart';
export 'brand_strings_en/liquid_glass.dart';
export 'brand_strings_en/re0.dart';
export 'brand_strings_en/star_rail.dart';
export 'brand_strings_en/wuthering.dart';
export 'brand_strings_en/yanyun.dart';
export 'brand_strings_en/zzz.dart';

/// Brand-specific copy. Every screen pulls strings from here so changing the
/// theme also changes wording (titles, tab labels, button text, empty
/// states, greetings).
class BrandStrings {
  // App-level
  final String appTitle;
  final String greetingMorning;
  final String greetingNoon;
  final String greetingAfternoon;
  final String greetingEvening;

  // Bottom navigation labels
  final String navToday;
  final String navTodo;
  final String navHabit;
  final String navCalendar;
  final String navFocus;
  final String navWidget;
  final String navMine;

  // Todo screen
  final String todoTitle;
  final String todoMatrixView;
  final String todoListView;
  final String todoEmpty;
  final String todoAddAction;
  final String todoCreateTitle;
  final String quadrantQ1Label; // urgent + important
  final String quadrantQ1Sub;
  final String quadrantQ2Label; // not-urgent + important
  final String quadrantQ2Sub;
  final String quadrantQ3Label; // urgent + not-important
  final String quadrantQ3Sub;
  final String quadrantQ4Label; // not-urgent + not-important
  final String quadrantQ4Sub;
  final String subtasksHeading;

  // Habit screen
  final String habitTitle;
  final String habitTabToday;
  final String habitTabHeatmap;
  final String habitEmpty;
  final String habitAddAction;
  final String habitCreateTitle;
  final String habitWeekOverview;
  final String habitHeatmapHeading;
  final String habitStreakLabel;
  final String habitTodayDone;

  // Calendar screen
  final String calendarTitle;
  final String calendarTabMonth;
  final String calendarTabWeek;
  final String calendarTabDay;
  final String calendarEmpty;
  final String calendarQuickAddTitle;

  // Focus / pomodoro screen
  final String focusTitle;
  final String focusTabTimer;
  final String focusTabHistory;
  final String focusStateFocus; // "专注中" equivalent
  final String focusStateShortBreak;
  final String focusStateLongBreak;
  final String focusCompletedSuffix; // "完成 X 次"
  final String focusEmpty;
  final String focusWhiteNoiseOn;
  final String focusWhiteNoiseOff;
  final String focusTaskLinkLabel;

  // Mine screen
  final String mineTitle;
  final String mineProductivityScore;
  final String mineSectionShortcuts;
  final String mineSectionSettings;
  final String mineAllTodos;
  final String mineAllHabits;
  final String mineDataDetail;
  final String mineThemeLabel;
  final String mineNotificationsLabel;
  final String mineCloudSyncLabel;
  final String mineDataMgmtLabel;
  final String mineAboutLabel;

  // Notification messages
  final String notifPomodoroDoneTitle;
  final String notifPomodoroDoneBody;
  final String notifBreakDoneTitle;
  final String notifBreakDoneBody;
  final String notifTodoDueTitle;
  final String notifHabitRemindTitle;

  /// 按时段返回问候语：深夜(0-6点)归入晚间问候，
  /// 其余为 早晨(6-12)/中午(12-14)/下午(14-18)/晚间(18-24)。
  String greetingFor(DateTime now) {
    final hour = now.hour;
    if (hour < 6) return greetingEvening;
    if (hour < 12) return greetingMorning;
    if (hour < 14) return greetingNoon;
    if (hour < 18) return greetingAfternoon;
    return greetingEvening;
  }

  const BrandStrings({
    required this.appTitle,
    required this.greetingMorning,
    required this.greetingNoon,
    required this.greetingAfternoon,
    required this.greetingEvening,
    required this.navToday,
    required this.navTodo,
    required this.navHabit,
    required this.navCalendar,
    required this.navFocus,
    required this.navWidget,
    required this.navMine,
    required this.todoTitle,
    required this.todoMatrixView,
    required this.todoListView,
    required this.todoEmpty,
    required this.todoAddAction,
    required this.todoCreateTitle,
    required this.quadrantQ1Label,
    required this.quadrantQ1Sub,
    required this.quadrantQ2Label,
    required this.quadrantQ2Sub,
    required this.quadrantQ3Label,
    required this.quadrantQ3Sub,
    required this.quadrantQ4Label,
    required this.quadrantQ4Sub,
    required this.subtasksHeading,
    required this.habitTitle,
    required this.habitTabToday,
    required this.habitTabHeatmap,
    required this.habitEmpty,
    required this.habitAddAction,
    required this.habitCreateTitle,
    required this.habitWeekOverview,
    required this.habitHeatmapHeading,
    required this.habitStreakLabel,
    required this.habitTodayDone,
    required this.calendarTitle,
    required this.calendarTabMonth,
    required this.calendarTabWeek,
    required this.calendarTabDay,
    required this.calendarEmpty,
    required this.calendarQuickAddTitle,
    required this.focusTitle,
    required this.focusTabTimer,
    required this.focusTabHistory,
    required this.focusStateFocus,
    required this.focusStateShortBreak,
    required this.focusStateLongBreak,
    required this.focusCompletedSuffix,
    required this.focusEmpty,
    required this.focusWhiteNoiseOn,
    required this.focusWhiteNoiseOff,
    required this.focusTaskLinkLabel,
    required this.mineTitle,
    required this.mineProductivityScore,
    required this.mineSectionShortcuts,
    required this.mineSectionSettings,
    required this.mineAllTodos,
    required this.mineAllHabits,
    required this.mineDataDetail,
    required this.mineThemeLabel,
    required this.mineNotificationsLabel,
    required this.mineCloudSyncLabel,
    required this.mineDataMgmtLabel,
    required this.mineAboutLabel,
    required this.notifPomodoroDoneTitle,
    required this.notifPomodoroDoneBody,
    required this.notifBreakDoneTitle,
    required this.notifBreakDoneBody,
    required this.notifTodoDueTitle,
    required this.notifHabitRemindTitle,
  });

  // ---- Default (no game skin) ----
  static const defaultBrand = BrandStrings(
    appTitle: '多仪',
    greetingMorning: '早上好',
    greetingNoon: '中午好',
    greetingAfternoon: '下午好',
    greetingEvening: '晚上好',
    navToday: '今日',
    navTodo: '待办',
    navHabit: '习惯',
    navCalendar: '日历',
    navFocus: '专注',
    navMine: '我的',
    navWidget: '小组件',
    todoTitle: '待办清单',
    todoMatrixView: '四象限',
    todoListView: '列表',
    todoEmpty: '暂无待办任务',
    todoAddAction: '添加任务',
    todoCreateTitle: '新建任务',
    quadrantQ1Label: '重要且紧急',
    quadrantQ1Sub: '马上做',
    quadrantQ2Label: '重要不紧急',
    quadrantQ2Sub: '计划做',
    quadrantQ3Label: '紧急不重要',
    quadrantQ3Sub: '委托做',
    quadrantQ4Label: '不重要不紧急',
    quadrantQ4Sub: '减少做',
    subtasksHeading: '子任务',
    habitTitle: '习惯',
    habitTabToday: '今日打卡',
    habitTabHeatmap: '热度图',
    habitEmpty: '今天没有习惯任务',
    habitAddAction: '添加习惯',
    habitCreateTitle: '新建习惯',
    habitWeekOverview: '本周概览',
    habitHeatmapHeading: '累计打卡热度',
    habitStreakLabel: '连续',
    habitTodayDone: '已完成',
    calendarTitle: '日历',
    calendarTabMonth: '月',
    calendarTabWeek: '周',
    calendarTabDay: '日',
    calendarEmpty: '这天没有安排',
    calendarQuickAddTitle: '新建待办',
    focusTitle: '番茄专注',
    focusTabTimer: '计时',
    focusTabHistory: '记录',
    focusStateFocus: '专注中',
    focusStateShortBreak: '短休息',
    focusStateLongBreak: '长休息',
    focusCompletedSuffix: '次专注',
    focusEmpty: '还没有专注记录',
    focusWhiteNoiseOn: '白噪音 ON',
    focusWhiteNoiseOff: '白噪音 OFF',
    focusTaskLinkLabel: '关联任务',
    mineTitle: '我的',
    mineProductivityScore: '综合评分',
    mineSectionShortcuts: '快捷入口',
    mineSectionSettings: '设置',
    mineAllTodos: '所有待办',
    mineAllHabits: '所有习惯',
    mineDataDetail: '数据详情',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '提醒偏好',
    mineCloudSyncLabel: '云同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '番茄钟完成',
    notifPomodoroDoneBody: '完成了一次专注，休息一下吧',
    notifBreakDoneTitle: '休息结束',
    notifBreakDoneBody: '准备好开始下一次专注了吗？',
    notifTodoDueTitle: '今日提醒',
    notifHabitRemindTitle: '习惯打卡提醒',
  );

  // ---- RE0 ----
  static const re0 = BrandStrings(
    appTitle: '多仪 · 露格尼卡',
    greetingMorning: '黎明已破，魔女',
    greetingNoon: '正午之光',
    greetingAfternoon: '午后之契',
    greetingEvening: '夜深了，回归者',
    navToday: '今朝',
    navTodo: '咒文',
    navHabit: '契约',
    navCalendar: '记忆回廊',
    navFocus: '咏唱',
    navMine: '试炼场',
    navWidget: '圣域',
    todoTitle: '咒文清单',
    todoMatrixView: '四象阵',
    todoListView: '咒文目录',
    todoEmpty: '咒文卷轴空空如也',
    todoAddAction: '编写新咒文',
    todoCreateTitle: '新建咒文',
    quadrantQ1Label: '即刻咏唱',
    quadrantQ1Sub: '紧急又重要',
    quadrantQ2Label: '魔法编排',
    quadrantQ2Sub: '重要不紧急',
    quadrantQ3Label: '使魔代办',
    quadrantQ3Sub: '紧急不重要',
    quadrantQ4Label: '丢入暗影',
    quadrantQ4Sub: '不重要不紧急',
    subtasksHeading: '附属咒文',
    habitTitle: '日常契约',
    habitTabToday: '今日契约',
    habitTabHeatmap: '契约热度',
    habitEmpty: '尚未签订任何契约',
    habitAddAction: '签订新契约',
    habitCreateTitle: '新建契约',
    habitWeekOverview: '本周契约履行',
    habitHeatmapHeading: '契约累计履行',
    habitStreakLabel: '连续履约',
    habitTodayDone: '今日已履约',
    calendarTitle: '记忆回廊',
    calendarTabMonth: '月相',
    calendarTabWeek: '周次',
    calendarTabDay: '当日',
    calendarEmpty: '这一天的回廊空空荡荡',
    calendarQuickAddTitle: '为这一天编写咒文',
    focusTitle: '咏唱仪式',
    focusTabTimer: '咏唱',
    focusTabHistory: '回声',
    focusStateFocus: '咏唱中',
    focusStateShortBreak: '玛那回流',
    focusStateLongBreak: '深度休眠',
    focusCompletedSuffix: '次咏唱已成',
    focusEmpty: '尚未留下任何咏唱回声',
    focusWhiteNoiseOn: '魔法低吟 ON',
    focusWhiteNoiseOff: '魔法低吟 OFF',
    focusTaskLinkLabel: '关联咒文',
    mineTitle: '试炼场',
    mineProductivityScore: '魔力评级',
    mineSectionShortcuts: '快捷契约',
    mineSectionSettings: '魔导设定',
    mineAllTodos: '全部咒文',
    mineAllHabits: '全部契约',
    mineDataDetail: '魔力档案',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '魔法提醒',
    mineCloudSyncLabel: '记忆同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '咏唱完成',
    notifPomodoroDoneBody: '玛那耗尽，请稍作休息',
    notifBreakDoneTitle: '玛那已恢复',
    notifBreakDoneBody: '准备好开始下一段咏唱了吗？',
    notifTodoDueTitle: '咒文即将失效',
    notifHabitRemindTitle: '契约提醒',
  );

  // ---- 原神 ----
  static const genshin = BrandStrings(
    appTitle: '多仪 · 提瓦特历',
    greetingMorning: '清晨，旅行者',
    greetingNoon: '正午元素活跃',
    greetingAfternoon: '午后好天气',
    greetingEvening: '夜幕降临，旅行者',
    navToday: '征途',
    navTodo: '冒险',
    navHabit: '日常',
    navCalendar: '日志',
    navFocus: '凝神',
    navMine: '行装',
    navWidget: '视界',
    todoTitle: '冒险委托',
    todoMatrixView: '元素阵',
    todoListView: '委托清单',
    todoEmpty: '冒险家协会暂无委托',
    todoAddAction: '接取新委托',
    todoCreateTitle: '新委托',
    quadrantQ1Label: '紧急派遣',
    quadrantQ1Sub: '元素失衡',
    quadrantQ2Label: '长期探索',
    quadrantQ2Sub: '稳步推进',
    quadrantQ3Label: '协助委托',
    quadrantQ3Sub: '可托付他人',
    quadrantQ4Label: '可暂搁置',
    quadrantQ4Sub: '暂无价值',
    subtasksHeading: '子任务',
    habitTitle: '每日委托',
    habitTabToday: '今日委托',
    habitTabHeatmap: '日常足迹',
    habitEmpty: '尚未在冒险家协会登记日常',
    habitAddAction: '登记新日常',
    habitCreateTitle: '新建日常',
    habitWeekOverview: '本周日常',
    habitHeatmapHeading: '冒险足迹热度',
    habitStreakLabel: '连续登记',
    habitTodayDone: '今日已完成',
    calendarTitle: '冒险日志',
    calendarTabMonth: '月',
    calendarTabWeek: '周',
    calendarTabDay: '日',
    calendarEmpty: '这一天没有冒险记录',
    calendarQuickAddTitle: '在这天接取委托',
    focusTitle: '凝神冥想',
    focusTabTimer: '冥想',
    focusTabHistory: '记录',
    focusStateFocus: '凝神中',
    focusStateShortBreak: '元素调息',
    focusStateLongBreak: '长时调息',
    focusCompletedSuffix: '次冥想已完成',
    focusEmpty: '还未开始冥想之旅',
    focusWhiteNoiseOn: '风之环响 ON',
    focusWhiteNoiseOff: '风之环响 OFF',
    focusTaskLinkLabel: '关联委托',
    mineTitle: '行装与档案',
    mineProductivityScore: '冒险等阶',
    mineSectionShortcuts: '快速通道',
    mineSectionSettings: '系统',
    mineAllTodos: '全部委托',
    mineAllHabits: '全部日常',
    mineDataDetail: '冒险档案',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '提醒偏好',
    mineCloudSyncLabel: '云端同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '冥想完成',
    notifPomodoroDoneBody: '元素已蓄满，去休息一下吧',
    notifBreakDoneTitle: '调息结束',
    notifBreakDoneBody: '继续启程?',
    notifTodoDueTitle: '委托即将到期',
    notifHabitRemindTitle: '日常提醒',
  );

  // ---- 星穹铁道 ----
  static const starRail = BrandStrings(
    appTitle: '多仪 · 列车日志',
    greetingMorning: '早安，开拓者',
    greetingNoon: '正午开拓时刻',
    greetingAfternoon: '午后跃迁',
    greetingEvening: '深空已至，开拓者',
    navToday: '巡游',
    navTodo: '开拓',
    navHabit: '行迹',
    navCalendar: '日历',
    navFocus: '跃迁',
    navMine: '档案',
    navWidget: '星图',
    todoTitle: '开拓任务',
    todoMatrixView: '星图阵',
    todoListView: '任务列表',
    todoEmpty: '列车待办空无一物',
    todoAddAction: '布置新任务',
    todoCreateTitle: '新任务',
    quadrantQ1Label: '紧急开拓',
    quadrantQ1Sub: '虚数失衡',
    quadrantQ2Label: '长线规划',
    quadrantQ2Sub: '星轨预设',
    quadrantQ3Label: '同伴协助',
    quadrantQ3Sub: '可委托其他成员',
    quadrantQ4Label: '搁置星海',
    quadrantQ4Sub: '低价值',
    subtasksHeading: '附属步骤',
    habitTitle: '每日行迹',
    habitTabToday: '今日行迹',
    habitTabHeatmap: '历程热度',
    habitEmpty: '尚未记录任何行迹',
    habitAddAction: '记录新行迹',
    habitCreateTitle: '新行迹',
    habitWeekOverview: '本周行迹',
    habitHeatmapHeading: '历程热度图',
    habitStreakLabel: '连续行迹',
    habitTodayDone: '今日已完成',
    calendarTitle: '列车日历',
    calendarTabMonth: '月',
    calendarTabWeek: '周',
    calendarTabDay: '日',
    calendarEmpty: '这一天列车未泊',
    calendarQuickAddTitle: '为这站派发任务',
    focusTitle: '跃迁仓',
    focusTabTimer: '跃迁',
    focusTabHistory: '航行记录',
    focusStateFocus: '跃迁中',
    focusStateShortBreak: '短停靠站',
    focusStateLongBreak: '长停靠站',
    focusCompletedSuffix: '次跃迁达成',
    focusEmpty: '尚未开启跃迁',
    focusWhiteNoiseOn: '深空噪声 ON',
    focusWhiteNoiseOff: '深空噪声 OFF',
    focusTaskLinkLabel: '关联任务',
    mineTitle: '档案室',
    mineProductivityScore: '开拓等级',
    mineSectionShortcuts: '快捷入口',
    mineSectionSettings: '系统',
    mineAllTodos: '全部任务',
    mineAllHabits: '全部行迹',
    mineDataDetail: '档案详情',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '提醒偏好',
    mineCloudSyncLabel: '云端同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '跃迁完成',
    notifPomodoroDoneBody: '能量耗尽，请稍作停靠',
    notifBreakDoneTitle: '停靠结束',
    notifBreakDoneBody: '准备开启下一次跃迁',
    notifTodoDueTitle: '任务即将到期',
    notifHabitRemindTitle: '行迹提醒',
  );

  // ---- 鸣潮 ----
  static const wuthering = BrandStrings(
    appTitle: '多仪 · 共鸣志',
    greetingMorning: '清晨，漂泊者',
    greetingNoon: '正午潮声',
    greetingAfternoon: '午后回响',
    greetingEvening: '夜潮渐起',
    navToday: '晨潮',
    navTodo: '声纹',
    navHabit: '回声',
    navCalendar: '潮汐',
    navFocus: '共鸣',
    navMine: '档案',
    navWidget: '声呐',
    todoTitle: '声纹列表',
    todoMatrixView: '声纹阵',
    todoListView: '声纹清单',
    todoEmpty: '尚未捕获任何声纹',
    todoAddAction: '采集新声纹',
    todoCreateTitle: '新声纹',
    quadrantQ1Label: '即时调律',
    quadrantQ1Sub: '尖锐共振',
    quadrantQ2Label: '长期声场',
    quadrantQ2Sub: '稳态频率',
    quadrantQ3Label: '协奏调律',
    quadrantQ3Sub: '可由同伴执行',
    quadrantQ4Label: '弱化频段',
    quadrantQ4Sub: '可减少',
    subtasksHeading: '子声纹',
    habitTitle: '日常回声',
    habitTabToday: '今日回声',
    habitTabHeatmap: '回响热度',
    habitEmpty: '尚未捕获回声',
    habitAddAction: '记录新回声',
    habitCreateTitle: '新回声',
    habitWeekOverview: '本周回声',
    habitHeatmapHeading: '回响热度图',
    habitStreakLabel: '连续回响',
    habitTodayDone: '今日已共鸣',
    calendarTitle: '潮汐表',
    calendarTabMonth: '月',
    calendarTabWeek: '周',
    calendarTabDay: '日',
    calendarEmpty: '这一天没有潮汐',
    calendarQuickAddTitle: '为这一天写下声纹',
    focusTitle: '共鸣腔',
    focusTabTimer: '共鸣',
    focusTabHistory: '回响记录',
    focusStateFocus: '共鸣中',
    focusStateShortBreak: '声场冷却',
    focusStateLongBreak: '深度冷却',
    focusCompletedSuffix: '次共鸣达成',
    focusEmpty: '尚未留下任何共鸣',
    focusWhiteNoiseOn: '潮汐噪声 ON',
    focusWhiteNoiseOff: '潮汐噪声 OFF',
    focusTaskLinkLabel: '关联声纹',
    mineTitle: '漂泊档案',
    mineProductivityScore: '共鸣等阶',
    mineSectionShortcuts: '快捷入口',
    mineSectionSettings: '系统',
    mineAllTodos: '全部声纹',
    mineAllHabits: '全部回声',
    mineDataDetail: '档案详情',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '提醒偏好',
    mineCloudSyncLabel: '云端同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '共鸣结束',
    notifPomodoroDoneBody: '声场耗散，去冷却一下吧',
    notifBreakDoneTitle: '冷却完成',
    notifBreakDoneBody: '是否再次共鸣?',
    notifTodoDueTitle: '声纹即将消散',
    notifHabitRemindTitle: '回声提醒',
  );

  // ---- 绝区零 ----
  static const zzz = BrandStrings(
    appTitle: '多仪 · 委托台',
    greetingMorning: '早，代理人',
    greetingNoon: '街区午时',
    greetingAfternoon: '午后霓虹',
    greetingEvening: '霓虹未眠',
    navToday: '班表',
    navTodo: '委托',
    navHabit: '日程',
    navCalendar: '档期',
    navFocus: '剪辑',
    navMine: '影碟',
    navWidget: '面板',
    todoTitle: '委托单',
    todoMatrixView: '霓虹阵',
    todoListView: '委托清单',
    todoEmpty: '邦布暂无委托',
    todoAddAction: '接新委托',
    todoCreateTitle: '新委托',
    quadrantQ1Label: '紧急行动',
    quadrantQ1Sub: '空洞蔓延',
    quadrantQ2Label: '长期任务',
    quadrantQ2Sub: '可慢慢做',
    quadrantQ3Label: '小队委托',
    quadrantQ3Sub: '丢给队友',
    quadrantQ4Label: '存档冷却',
    quadrantQ4Sub: '可放置',
    subtasksHeading: '子项',
    habitTitle: '每日日程',
    habitTabToday: '今日日程',
    habitTabHeatmap: '街区热度',
    habitEmpty: '尚未排入任何日程',
    habitAddAction: '排入新日程',
    habitCreateTitle: '新日程',
    habitWeekOverview: '本周日程',
    habitHeatmapHeading: '街区活动热度',
    habitStreakLabel: '连续在岗',
    habitTodayDone: '今日已完成',
    calendarTitle: '档期',
    calendarTabMonth: '月',
    calendarTabWeek: '周',
    calendarTabDay: '日',
    calendarEmpty: '这一天没有委托',
    calendarQuickAddTitle: '为这一天加入委托',
    focusTitle: '录像剪辑',
    focusTabTimer: '剪辑',
    focusTabHistory: '影碟',
    focusStateFocus: '剪辑中',
    focusStateShortBreak: '小憩',
    focusStateLongBreak: '长休',
    focusCompletedSuffix: '段剪辑完成',
    focusEmpty: '影碟仓库还是空的',
    focusWhiteNoiseOn: '街区噪声 ON',
    focusWhiteNoiseOff: '街区噪声 OFF',
    focusTaskLinkLabel: '关联委托',
    mineTitle: '档案柜',
    mineProductivityScore: '代理人等级',
    mineSectionShortcuts: '快捷入口',
    mineSectionSettings: '系统',
    mineAllTodos: '全部委托',
    mineAllHabits: '全部日程',
    mineDataDetail: '档案',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '提醒偏好',
    mineCloudSyncLabel: '云端同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '剪辑完成',
    notifPomodoroDoneBody: '影碟已存档，先休息一下',
    notifBreakDoneTitle: '休息结束',
    notifBreakDoneBody: '准备开始下一段剪辑',
    notifTodoDueTitle: '委托即将到期',
    notifHabitRemindTitle: '日程提醒',
  );

  // ---- 燕云十六声 ----
  static const yanyun = BrandStrings(
    appTitle: '多仪 · 江湖卷',
    greetingMorning: '晨光熹微，少侠',
    greetingNoon: '正午江湖',
    greetingAfternoon: '午后茶香',
    greetingEvening: '夜幕初临',
    navToday: '晨钟',
    navTodo: '江湖事',
    navHabit: '日课',
    navCalendar: '光阴册',
    navFocus: '入定',
    navMine: '行囊',
    navWidget: '密函',
    todoTitle: '江湖待办',
    todoMatrixView: '阴阳阵',
    todoListView: '名册',
    todoEmpty: '江湖一片清静',
    todoAddAction: '记下江湖事',
    todoCreateTitle: '新事',
    quadrantQ1Label: '即刻起手',
    quadrantQ1Sub: '风急火烈',
    quadrantQ2Label: '从长计议',
    quadrantQ2Sub: '徐徐图之',
    quadrantQ3Label: '托付门人',
    quadrantQ3Sub: '可由旁人代行',
    quadrantQ4Label: '随风而散',
    quadrantQ4Sub: '不必计较',
    subtasksHeading: '细则',
    habitTitle: '日课表',
    habitTabToday: '今日日课',
    habitTabHeatmap: '功夫热度',
    habitEmpty: '尚未立下日课',
    habitAddAction: '立下日课',
    habitCreateTitle: '新日课',
    habitWeekOverview: '本周日课',
    habitHeatmapHeading: '修行热度图',
    habitStreakLabel: '连续修行',
    habitTodayDone: '今日已勤勉',
    calendarTitle: '光阴册',
    calendarTabMonth: '月相',
    calendarTabWeek: '七日',
    calendarTabDay: '今朝',
    calendarEmpty: '这一日江湖无事',
    calendarQuickAddTitle: '在这一日记下',
    focusTitle: '入定',
    focusTabTimer: '入定',
    focusTabHistory: '功课录',
    focusStateFocus: '入定中',
    focusStateShortBreak: '小憩',
    focusStateLongBreak: '闭关',
    focusCompletedSuffix: '次入定已成',
    focusEmpty: '尚未留下功课',
    focusWhiteNoiseOn: '松涛 ON',
    focusWhiteNoiseOff: '松涛 OFF',
    focusTaskLinkLabel: '关联事项',
    mineTitle: '行囊',
    mineProductivityScore: '江湖名望',
    mineSectionShortcuts: '快捷',
    mineSectionSettings: '设置',
    mineAllTodos: '全部江湖事',
    mineAllHabits: '全部日课',
    mineDataDetail: '行囊详情',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '提醒偏好',
    mineCloudSyncLabel: '云端同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '入定完成',
    notifPomodoroDoneBody: '已成一段功课，且去歇歇',
    notifBreakDoneTitle: '小憩已尽',
    notifBreakDoneBody: '可继续下一段功夫',
    notifTodoDueTitle: '江湖事将至',
    notifHabitRemindTitle: '日课提醒',
  );

  // ---- 希卡之石 (BOTW) ----
  static const botw = BrandStrings(
    appTitle: '多仪 · 希卡石板',
    greetingMorning: '晨光未明，林克',
    greetingNoon: '正午海拉鲁',
    greetingAfternoon: '午后阳光',
    greetingEvening: '夜之海拉鲁',
    navToday: '晨曦',
    navTodo: '符文',
    navHabit: '修行',
    navCalendar: '石板',
    navFocus: '具现',
    navMine: '希卡',
    navWidget: '希卡镜',
    todoTitle: '符文清单',
    todoMatrixView: '符文阵',
    todoListView: '符文目录',
    todoEmpty: '石板上空无符文',
    todoAddAction: '刻下新符文',
    todoCreateTitle: '新符文',
    quadrantQ1Label: '即时具现',
    quadrantQ1Sub: '危机刻不容缓',
    quadrantQ2Label: '长期任务',
    quadrantQ2Sub: '稳步前行',
    quadrantQ3Label: '伙伴协力',
    quadrantQ3Sub: '可由同伴完成',
    quadrantQ4Label: '尘封档案',
    quadrantQ4Sub: '低优先',
    subtasksHeading: '子符文',
    habitTitle: '修行日课',
    habitTabToday: '今日修行',
    habitTabHeatmap: '修行热度',
    habitEmpty: '尚无修行记录',
    habitAddAction: '记录新修行',
    habitCreateTitle: '新修行',
    habitWeekOverview: '本周修行',
    habitHeatmapHeading: '修行热度图',
    habitStreakLabel: '连续修行',
    habitTodayDone: '今日已完成',
    calendarTitle: '希卡石板',
    calendarTabMonth: '月',
    calendarTabWeek: '周',
    calendarTabDay: '日',
    calendarEmpty: '这一天石板上空空如也',
    calendarQuickAddTitle: '在这一天刻下',
    focusTitle: '具现化',
    focusTabTimer: '具现',
    focusTabHistory: '记录',
    focusStateFocus: '具现化中',
    focusStateShortBreak: '能量回流',
    focusStateLongBreak: '深度回流',
    focusCompletedSuffix: '次具现已成',
    focusEmpty: '尚未启动具现化',
    focusWhiteNoiseOn: '神庙白噪 ON',
    focusWhiteNoiseOff: '神庙白噪 OFF',
    focusTaskLinkLabel: '关联符文',
    mineTitle: '希卡之石',
    mineProductivityScore: '希卡等级',
    mineSectionShortcuts: '快捷',
    mineSectionSettings: '系统',
    mineAllTodos: '全部符文',
    mineAllHabits: '全部修行',
    mineDataDetail: '希卡档案',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '提醒偏好',
    mineCloudSyncLabel: '云端同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '具现完成',
    notifPomodoroDoneBody: '能量耗尽，回流一下吧',
    notifBreakDoneTitle: '能量已回流',
    notifBreakDoneBody: '准备开启下一次具现',
    notifTodoDueTitle: '符文即将失效',
    notifHabitRemindTitle: '修行提醒',
  );

  // ---- 液态玻璃 ----
  static const liquidGlass = BrandStrings(
    appTitle: '多仪 · 液态玻璃',
    greetingMorning: '早上好',
    greetingNoon: '午安',
    greetingAfternoon: '午后好',
    greetingEvening: '晚上好',
    navToday: '今天',
    navTodo: '待办',
    navHabit: '习惯',
    navCalendar: '日历',
    navFocus: '专注',
    navMine: '我的',
    navWidget: '小组件',
    todoTitle: '待办事项',
    todoMatrixView: '四象限',
    todoListView: '列表',
    todoEmpty: '还没有待办事项',
    todoAddAction: '添加待办',
    todoCreateTitle: '新待办',
    quadrantQ1Label: '重要且紧急',
    quadrantQ1Sub: '立即处理',
    quadrantQ2Label: '重要不紧急',
    quadrantQ2Sub: '安排计划',
    quadrantQ3Label: '紧急不重要',
    quadrantQ3Sub: '快速处理',
    quadrantQ4Label: '不重要不紧急',
    quadrantQ4Sub: '稍后处理',
    subtasksHeading: '子任务',
    habitTitle: '习惯',
    habitTabToday: '今日打卡',
    habitTabHeatmap: '打卡热度',
    habitEmpty: '今天没有待打卡的习惯',
    habitAddAction: '添加习惯',
    habitCreateTitle: '新习惯',
    habitWeekOverview: '本周概览',
    habitHeatmapHeading: '打卡热度统计',
    habitStreakLabel: '连续',
    habitTodayDone: '已完成',
    calendarTitle: '日历',
    calendarTabMonth: '月',
    calendarTabWeek: '周',
    calendarTabDay: '日',
    calendarEmpty: '这一天暂无安排',
    calendarQuickAddTitle: '新建日程',
    focusTitle: '专注',
    focusTabTimer: '计时',
    focusTabHistory: '记录',
    focusStateFocus: '专注中',
    focusStateShortBreak: '短休息',
    focusStateLongBreak: '长休息',
    focusCompletedSuffix: '次专注',
    focusEmpty: '暂无专注记录',
    focusWhiteNoiseOn: '白噪音 开',
    focusWhiteNoiseOff: '白噪音 关',
    focusTaskLinkLabel: '关联任务',
    mineTitle: '我的',
    mineProductivityScore: '效率评分',
    mineSectionShortcuts: '快捷入口',
    mineSectionSettings: '设置',
    mineAllTodos: '全部待办',
    mineAllHabits: '全部习惯',
    mineDataDetail: '数据详情',
    mineThemeLabel: '主题风格',
    mineNotificationsLabel: '提醒偏好',
    mineCloudSyncLabel: '云同步',
    mineDataMgmtLabel: '数据管理',
    mineAboutLabel: '关于多仪',
    notifPomodoroDoneTitle: '专注完成',
    notifPomodoroDoneBody: '本次专注已完成，休息一下吧',
    notifBreakDoneTitle: '休息结束',
    notifBreakDoneBody: '准备好开始下一段专注了吗？',
    notifTodoDueTitle: '待办提醒',
    notifHabitRemindTitle: '习惯打卡提醒',
  );

  static BrandStrings forStyle(BrandStyle style) {
    switch (style) {
      case BrandStyle.defaultBrand:
        return defaultBrand;
      case BrandStyle.re0:
        return re0;
      case BrandStyle.genshin:
        return genshin;
      case BrandStyle.starRail:
        return starRail;
      case BrandStyle.wuthering:
        return wuthering;
      case BrandStyle.zzz:
        return zzz;
      case BrandStyle.yanyun:
        return yanyun;
      case BrandStyle.botw:
        return botw;
      case BrandStyle.liquidGlass:
        return liquidGlass;
    }
  }

  /// 按语言分发主题文案：en 命中英文变体（lib/core/brand_strings_en/，
  /// 值为已翻译的英文文案），其余语言走 zh 常量。
  static BrandStrings forLocale(BrandStyle style, AppLocale locale) {
    if (locale == AppLocale.en) {
      switch (style) {
        case BrandStyle.defaultBrand:
          return enDefaultBrand;
        case BrandStyle.re0:
          return enRe0;
        case BrandStyle.genshin:
          return enGenshin;
        case BrandStyle.starRail:
          return enStarRail;
        case BrandStyle.wuthering:
          return enWuthering;
        case BrandStyle.zzz:
          return enZzz;
        case BrandStyle.yanyun:
          return enYanyun;
        case BrandStyle.botw:
          return enBotw;
        case BrandStyle.liquidGlass:
          return enLiquidGlass;
      }
    }
    return forStyle(style);
  }
}
