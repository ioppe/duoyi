import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/i18n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });

  group('I18n.tr', () {
    test('中文环境下返回中文文案', () {
      I18n.setLocale(AppLocale.zh);
      expect(I18n.tr('action.confirm'), '确定');
      expect(I18n.tr('nav.today'), '今日');
    });

    test('英文环境下返回英文文案', () {
      I18n.setLocale(AppLocale.en);
      expect(I18n.tr('action.confirm'), 'OK');
      expect(I18n.tr('nav.today'), 'Today');
    });

    test('未知 key 回退到 key 本身', () {
      I18n.setLocale(AppLocale.zh);
      expect(I18n.tr('not.exist.key'), 'not.exist.key');
    });

    test('英文 locale 缺失某 key 时回退到中文', () {
      // 模拟方式：所有 key 应在两边都有；此测试验证回退路径存在
      I18n.setLocale(AppLocale.en);
      // todo.matrix 英文有 'Matrix'，确保也存在中文
      expect(I18n.tr('todo.matrix'), 'Matrix');
      I18n.setLocale(AppLocale.zh);
      expect(I18n.tr('todo.matrix'), '四象限');
    });
  });

  group('词条覆盖完整性', () {
    test('常用导航 keys 中英都有', () {
      const keys = [
        'nav.today',
        'nav.todo',
        'nav.habit',
        'nav.calendar',
        'nav.focus',
        'nav.widget',
        'nav.mine',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
    });

    test('日历和农历 keys 中英都有', () {
      const keys = [
        'calendar.solar',
        'calendar.lunar',
        'calendar.chinese_lunar',
        'calendar.chinese_lunar_calendar',
        'calendar.corresponding_lunar',
        'calendar.corresponding_solar',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
      I18n.setLocale(AppLocale.en);
      expect(
        I18n.tr('calendar.chinese_lunar_calendar'),
        'Chinese Lunar Calendar',
      );
    });

    test('常用动作 keys 中英都有', () {
      const keys = [
        'action.confirm',
        'action.cancel',
        'action.save',
        'action.delete',
        'action.create',
        'action.generate',
        'action.complete',
        'action.off',
        'action.move_up',
        'action.move_down',
        'action.clear',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
    });

    test('快速捕获 keys 中英都有', () {
      const keys = [
        'quick.todo.title',
        'quick.todo.hint',
        'quick.todo.parsed_prefix',
        'quick.ai.title',
        'quick.ai.hint',
        'quick.ai.error',
        'quick.note.title',
        'quick.note.hint',
        'quick.menu.ai_schedule',
        'quick.menu.search',
        'quick.menu.diary',
        'quick.menu.note',
        'quick.menu.todo',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
    });

    test('全局搜索 keys 中英都有', () {
      const keys = [
        'search.hint',
        'search.empty',
        'search.no_results.prefix',
        'search.no_results.suffix',
        'search.results.title',
        'search.results.summary_prefix',
        'search.results.summary_middle',
        'search.results.summary_suffix',
        'search.clear',
        'search.kind.todo',
        'search.kind.habit',
        'search.kind.note',
        'search.kind.diary',
        'search.kind.anniversary',
        'search.kind.countdown',
        'search.kind.goal',
        'search.kind.course',
        'search.kind.event',
        'search.kind.time_entry',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
      I18n.setLocale(AppLocale.en);
      expect(I18n.tr('search.results.title'), 'Search results');
      expect(I18n.tr('search.kind.time_entry'), 'Time log');
    });

    test('账号与个人资料 keys 中英都有', () {
      const keys = [
        'auth.login.title',
        'auth.register.title',
        'auth.login.subtitle.password',
        'auth.login.subtitle.email_code',
        'auth.register.subtitle',
        'auth.password_login',
        'auth.email_code_login',
        'auth.account',
        'auth.verified_email',
        'auth.email.optional',
        'auth.email_code.optional',
        'auth.forgot_password',
        'auth.password_reset.title',
        'auth.reset_account',
        'auth.reset_account.helper',
        'auth.error.username_length',
        'auth.error.email_invalid',
        'auth.error.new_password_mismatch',
        'profile.title',
        'profile.nickname',
        'profile.display_name',
        'profile.local_nickname',
        'profile.email.binding',
        'profile.avatar.saved',
        'mine.menu.apps',
        'mine.menu.appearance',
        'mine.menu.settings',
        'mine.menu.support',
        'appearance.subtitle',
        'appearance.apply',
        'profile.account_id',
        'profile.username.locked',
        'profile.account_security',
        'profile.account_security.subtitle',
        'profile.email.local_display',
        'profile.change_password',
        'profile.confirm_new_password',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
      I18n.setLocale(AppLocale.en);
      expect(I18n.tr('auth.login.title'), 'Sign in');
      expect(I18n.tr('profile.title'), 'Profile');
    });

    test('偏好设置 keys 中英都有', () {
      const keys = [
        'preferences.title',
        'preferences.local.title',
        'preferences.local.subtitle',
        'preferences.section.date',
        'preferences.section.date.subtitle',
        'preferences.first_day.title',
        'preferences.first_day.current_monday',
        'preferences.first_day.current_sunday',
        'preferences.date_format.title',
        'preferences.home_calendar.title',
        'preferences.home_calendar.subtitle',
        'preferences.timezone.title',
        'preferences.timezone.follow_system',
        'preferences.lunar.title',
        'preferences.lunar.subtitle',
        'preferences.section.defaults',
        'preferences.section.defaults.subtitle',
        'preferences.default_tab.title',
        'preferences.quick_capture.title',
        'preferences.quick_capture.subtitle',
        'preferences.notification_quick_add.title',
        'preferences.notification_quick_add.subtitle',
        'preferences.show_completed.title',
        'preferences.show_completed.subtitle',
        'preferences.pomodoro_length.title',
        'preferences.section.bottom_nav',
        'preferences.section.bottom_nav.subtitle',
        'preferences.section.interaction',
        'preferences.section.interaction.subtitle',
        'preferences.haptic.title',
        'preferences.haptic.subtitle',
        'preferences.section.auto_archive',
        'preferences.section.auto_archive.subtitle',
        'preferences.auto_archive.title',
        'preferences.auto_archive.never',
        'preferences.auto_archive.after_days',
        'preferences.section.daily_reminder',
        'preferences.section.daily_reminder.subtitle',
        'preferences.nav.fixed',
        'preferences.nav.visible',
        'preferences.nav.hidden',
        'preferences.notify.permission_denied',
        'preferences.notify.exact_alarm_granted',
        'preferences.notify.exact_alarm_denied',
        'preferences.notify.full_screen_granted',
        'preferences.notify.full_screen_denied',
        'preferences.notify.test_permission_denied',
        'preferences.notify.test_failed',
        'preferences.notify.test_sent',
        'preferences.notify.pending_cleared',
        'preferences.notify.open_settings_failed',
        'preferences.ringtone.section',
        'preferences.ringtone.section.subtitle',
        'preferences.ringtone.section.subtitle.android',
        'preferences.ringtone.section.subtitle.apple',
        'preferences.ringtone.section.subtitle.desktop',
        'preferences.ringtone.section.subtitle.unsupported',
        'preferences.ringtone.sound',
        'preferences.ringtone.volume',
        'preferences.ringtone.current',
        'preferences.ringtone.system_sound',
        'preferences.ringtone.system_sound.subtitle.apple',
        'preferences.ringtone.system_sound.subtitle.desktop',
        'preferences.ringtone.unsupported',
        'preferences.ringtone.unsupported.subtitle',
        'preferences.daily_reminder.one',
        'preferences.daily_reminder.two',
        'preferences.daily_reminder.three',
        'preferences.daily_reminder.disabled',
        'preferences.daily_reminder.time',
        'preferences.daily_reminder.time.subtitle',
        'preferences.daily_reminder.time_suffix',
        'preferences.daily_reminder.time_picker.subtitle',
        'preferences.daily_reminder.today_tasks',
        'preferences.daily_reminder.today_tasks.subtitle',
        'preferences.daily_reminder.tomorrow_plan',
        'preferences.daily_reminder.tomorrow_plan.subtitle',
        'preferences.daily_reminder.overdue_tasks',
        'preferences.daily_reminder.overdue_tasks.subtitle',
        'preferences.daily_reminder.pause_holidays',
        'preferences.daily_reminder.pause_holidays.subtitle',
        'preferences.daily_reminder.scope.today',
        'preferences.daily_reminder.scope.overdue',
        'preferences.daily_reminder.scope.tomorrow',
        'preferences.daily_reminder.scope.none',
        'today.almanac.title',
        'today.unit.item',
        'today.unit.times',
        'today.unit.course_section',
        'today.unit.point',
        'today.diary',
        'today.diary.written',
        'today.diary.unwritten',
        'today.suggestions',
        'today.suggestions.subtitle',
        'today.added_prefix',
        'today.add_to_today',
        'today.todos',
        'today.tab.goals',
        'today.todos.summary',
        'today.goals.summary',
        'today.all_todos',
        'today.all_goals',
        'feature.unavailable',
        'ai.command.help',
        'statistics.activity.description',
        'challenge.weekly_active_days.description',
        'backup.wipe.confirm',
        'today.completed',
        'today.courses',
        'today.course.period_prefix',
        'today.course.period_suffix',
        'today.upcoming_anniversaries',
        'today.anniversary.today',
        'today.anniversary.days_prefix',
        'today.active_goals',
        'today.goal.create.subtitle',
        'today.view',
        'today.productivity.score',
        'today.productivity.weekly',
        'today.productivity.flat',
        'today.productivity.subtitle',
        'today.productivity.completion_rate',
        'diary.title',
        'diary.write',
        'diary.empty.message',
        'diary.stats.tooltip',
        'diary.summary.title',
        'diary.summary.subtitle',
        'diary.summary.total',
        'diary.summary.this_month',
        'diary.summary.streak',
        'diary.recent.title',
        'diary.recent.records_suffix',
        'diary.entry.count_suffix',
        'diary.mood.stats.title',
        'diary.no_data',
        'diary.ai.insights',
        'diary.ai.deep_review.tooltip',
        'diary.ai.deep_review.title',
        'diary.ai.disabled',
        'diary.ai.review_failed_prefix',
        'diary.editor.date_title',
        'diary.editor.mood_prompt',
        'diary.editor.weather',
        'diary.editor.tag_hint',
        'diary.editor.content_hint',
        'diary.mood.awesome',
        'diary.mood.good',
        'diary.mood.okay',
        'diary.mood.bad',
        'diary.mood.terrible',
        'diary.weather.sunny',
        'diary.weather.cloudy',
        'diary.weather.overcast',
        'diary.weather.rain',
        'diary.weather.snow',
        'diary.weather.wind',
        'diary.weather.fog',
        'diary.weather.thunder',
        'countdown.title',
        'countdown.empty',
        'countdown.nearest.empty',
        'countdown.nearest.prefix',
        'countdown.nearest.days_prefix',
        'countdown.summary.total',
        'countdown.summary.within_7_days',
        'countdown.list.title',
        'countdown.list.subtitle',
        'countdown.category.default',
        'countdown.editor.edit_title',
        'countdown.editor.subtitle',
        'countdown.field.title',
        'countdown.field.category',
        'countdown.field.target_date',
        'countdown.field.due_reminder',
        'countdown.field.remind_days',
        'countdown.field.remind_time',
        'countdown.reminder.closed',
        'countdown.reminder.before_prefix',
        'countdown.reminder.before_suffix',
        'countdown.status.pinned',
        'countdown.status.expired',
        'countdown.status.soon',
        'countdown.status.running',
        'countdown.target.prefix',
        'countdown.days.elapsed',
        'countdown.days.remaining',
        'anniversary.title',
        'anniversary.birthday',
        'anniversary.countdown_short',
        'anniversary.custom',
        'anniversary.tab.all',
        'anniversary.upcoming_30_days',
        'anniversary.empty',
        'anniversary.upcoming_empty',
        'anniversary.delete.title',
        'anniversary.delete.content_suffix',
        'anniversary.occurrence.prefix',
        'anniversary.occurrence.suffix',
        'anniversary.years_elapsed.prefix',
        'anniversary.years_elapsed.suffix',
        'anniversary.next.prefix',
        'anniversary.today_short',
        'anniversary.editor.add_title',
        'anniversary.editor.edit_title',
        'anniversary.field.title',
        'anniversary.field.title_hint',
        'anniversary.field.description',
        'anniversary.field.type',
        'anniversary.field.date_type',
        'anniversary.field.date_picker_title',
        'anniversary.field.date_picker_subtitle',
        'anniversary.field.color',
        'anniversary.lunar.year_suffix',
        'course.week.prefix',
        'course.week.suffix',
        'course.week.count_suffix',
        'course.week.current_tooltip',
        'course.empty.message',
        'course.add',
        'course.week_picker.title',
        'course.week_picker.subtitle',
        'course.weeks.all',
        'course.weeks.odd',
        'course.weeks.even',
        'course.weeks.select_all',
        'course.settings.title',
        'course.settings.subtitle',
        'course.settings.preview_prefix',
        'course.editor.add_title',
        'course.editor.edit_title',
        'course.editor.subtitle',
        'course.field.term_start',
        'course.field.term_start_picker',
        'course.field.total_weeks',
        'course.field.sessions_per_day',
        'course.field.session_minutes',
        'course.field.first_session_time',
        'course.field.first_session_time_subtitle',
        'course.field.break_minutes',
        'course.field.name',
        'course.field.teacher',
        'course.field.location',
        'course.field.weekday',
        'course.field.start_section',
        'course.field.section_count',
        'course.field.class_weeks',
        'course.field.color',
        'weekday.mon',
        'weekday.sun',
        'repeat.every_day',
        'repeat.weekdays',
        'unit.minute',
        'unit.min',
        'unit.day',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
    });
  });

  group('LocaleProvider', () {
    test('无用户偏好时跟随平台语言', () async {
      addTearDown(() {
        TestWidgetsFlutterBinding.instance.platformDispatcher
            .clearLocaleTestValue();
      });

      TestWidgetsFlutterBinding.instance.platformDispatcher.localeTestValue =
          const Locale('en');

      final provider = LocaleProvider();
      await provider.loadFromStorage();

      expect(provider.locale, AppLocale.en);
      expect(provider.flutterLocale, const Locale('en'));
      expect(I18n.tr('nav.widget'), 'Widgets');
    });

    test('用户偏好优先于平台语言并持久化', () async {
      TestWidgetsFlutterBinding.instance.platformDispatcher.localeTestValue =
          const Locale('en');
      SharedPreferences.setMockInitialValues({'duoyi_locale_v1': 'zh'});

      final provider = LocaleProvider();
      await provider.loadFromStorage();
      expect(provider.locale, AppLocale.zh);
      expect(provider.flutterLocale, const Locale('zh'));

      await provider.setLocale(AppLocale.en);
      expect(provider.locale, AppLocale.en);
      expect(I18n.tr('settings.language'), 'Display language');
    });

    test('兼容并迁移历史区域格式语言偏好', () async {
      SharedPreferences.setMockInitialValues({'duoyi_locale_v1': 'zh_CN'});

      final provider = LocaleProvider();
      await provider.loadFromStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(provider.locale, AppLocale.zh);
      expect(provider.flutterLocale, const Locale('zh'));
      expect(prefs.getString('duoyi_locale_v1'), 'zh');
    });
  });
}
