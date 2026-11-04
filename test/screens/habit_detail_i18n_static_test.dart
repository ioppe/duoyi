import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('习惯详情页固定文案迁移到 I18n', () {
    final detail = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final dateFields = File(
      'lib/widgets/habit_date_range_fields.dart',
    ).readAsStringSync();
    final source = '$detail\n$dateFields';

    expect(detail, contains("import '../services/alarm_service.dart';"));
    expect(
      detail,
      contains('AlarmService.instance.requestExactAlarmPermission()'),
    );
    expect(detail, contains('.requestFullScreenIntentPermission()'));
    expect(
      detail,
      isNot(contains('onRequestExactAlarmPermission: () async {}')),
    );
    expect(
      detail,
      isNot(contains('onRequestFullScreenIntentPermission: () async {}')),
    );

    for (final key in [
      'habit.detail.title',
      'habit.detail.not_found',
      'habit.edit.title',
      'habit.saved',
      'habit.field.name',
      'habit.field.group',
      'habit.field.group.empty_hint',
      'habit.field.daily_target_count',
      'habit.field.unit',
      'habit.unit.times',
      'habit.kind',
      'habit.kind.positive',
      'habit.kind.negative',
      'habit.color',
      'habit.reminder',
      'habit.error.name_required',
      'habit.error.daily_target',
      'habit.error.flex_target',
      'habit.error.date_range',
      'habit.error.notification_permission',
      'habit.error.reminder_register_failed',
      'habit.flex.rule',
      'habit.flex.period_target',
      'habit.flex.period_target_hint',
      'habit.flex.daily_note',
      'habit.flex.negative_note',
      'habit.stat.current_streak',
      'habit.stat.best_streak',
      'habit.stat.today',
      'habit.heatmap.title',
      'habit.calendar.title',
      'habit.calendar.hint',
      'habit.calendar.expanded_hint',
      'habit.calendar.expand',
      'habit.calendar.collapse',
      'habit.calendar.previous_month',
      'habit.calendar.next_month',
      'habit.day.pending',
      'habit.day.future',
      'habit.day.count',
      'habit.day.target',
      'habit.records.inactive',
      'habit.records.undo_once',
      'habit.records.record_once',
      'habit.records.make_up_once',
      'habit.trend.title',
      'habit.trend.completed',
      'habit.trend.daily_average',
      'habit.trend.longest_streak',
      'habit.trend.vs_previous',
      'habit.trend.bucket_details',
      'habit.trend.one_year',
      'habit.date_range.title',
      'habit.date_range.start',
      'habit.date_range.end',
      'habit.date_range.start_empty',
      'habit.date_range.end_empty',
      'habit.date_range.pick_start',
      'habit.date_range.pick_end',
      'preferences.notify.open_settings_failed',
      'action.back',
      'action.clear',
      'action.edit',
      'unit.day',
    ]) {
      expect(source, contains("'$key'"), reason: key);
    }

    final generatedBase = File(
      'lib/l10n/generated/app_localizations.dart',
    ).readAsStringSync();
    final generatedZh = File(
      'lib/l10n/generated/app_localizations_zh.dart',
    ).readAsStringSync();
    final generatedEn = File(
      'lib/l10n/generated/app_localizations_en.dart',
    ).readAsStringSync();
    expect(
      generatedBase,
      contains('String get habitErrorReminderRegisterFailed;'),
    );
    expect(
      generatedZh,
      contains("String get habitErrorReminderRegisterFailed => '习惯提醒注册失败';"),
    );
    expect(
      generatedEn,
      contains('String get habitErrorReminderRegisterFailed =>'),
    );

    for (final hardcoded in [
      "'请填写习惯名称'",
      "'每日目标次数至少为 1'",
      "'周期目标至少为 1'",
      "'结束日期不能早于开始日期'",
      "'系统通知未授权，习惯提醒不会响铃或弹出'",
      "'已保存'",
      "'编辑习惯'",
      "'习惯名称'",
      "'分组'",
      "'留空则归入未分组'",
      "'每日目标次数'",
      "'单位'",
      "'弹性打卡规则'",
      "'每周目标'",
      "'每月目标'",
      "'目标次数'",
      "'例如每周目标 5 次'",
      "'关闭时按每日目标连续统计'",
      "'反向戒除按每日不发生统计'",
      "'习惯类型'",
      "'颜色'",
      "'提醒'",
      "'习惯详情'",
      "'这个习惯不存在或已被删除'",
      "'返回'",
      "'编辑'",
      "'当前连续'",
      "'最佳纪录'",
      "'今日'",
      "'打卡热力图'",
      "'最近记录 / 补卡'",
      "'未在周期内'",
      "'撤回一次'",
      "'记录一次'",
      "'补一次'",
      "'习惯趋势'",
      "'达标'",
      "'日均'",
      "'最长连续'",
      "'较上期'",
      "'区间明细'",
      "'无法打开系统设置'",
      "'习惯周期'",
      "'开始日期'",
      "'结束日期'",
      "'立即开始'",
      "'不设结束'",
      "'选择开始日期'",
      "'选择结束日期'",
      "'清除'",
    ]) {
      expect(source, isNot(contains(hardcoded)), reason: hardcoded);
    }
  });
}
