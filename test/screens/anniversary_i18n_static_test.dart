import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('纪念日页面固定文案迁移到 I18n', () {
    final source = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();

    for (final key in [
      'anniversary.title',
      'anniversary.birthday',
      'anniversary.countdown_short',
      'anniversary.custom',
      'anniversary.tab.all',
      'anniversary.upcoming_30_days',
      'anniversary.empty',
      'anniversary.upcoming_empty',
      'anniversary.summary.within_30_days',
      'anniversary.list.suffix',
      'anniversary.list.subtitle',
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
      'anniversary.validation.title_required',
      'anniversary.saved',
      'anniversary.save_failed_prefix',
      'anniversary.reminder.register_failed',
      'anniversary.reminder.not_registered',
      'anniversary.reminder.popup_fallback_failed',
      'anniversary.reminder.popup_permission_denied',
      'anniversary.reminder.popup_warning',
      'anniversary.reminder.alarm_permission_denied',
      'anniversary.reminder.alarm_channel_missing',
      'anniversary.reminder.exact_alarm_missing',
      'anniversary.reminder.fullscreen_missing',
      'anniversary.reminder.email_warning',
      'anniversary.reminder.exception_prefix',
      'anniversary.reminder.saved_prefix',
      'anniversary.reminder.time_past',
      'anniversary.lunar.year_suffix',
      'reminder.kind.push',
      'reminder.kind.popup',
      'reminder.kind.alarm',
      'reminder.kind.off',
      'countdown.field.due_reminder',
      'countdown.field.remind_days',
      'countdown.field.remind_time',
      'countdown.reminder.closed',
      'countdown.reminder.before_prefix',
      'countdown.reminder.before_suffix',
      'calendar.solar',
      'calendar.lunar',
      'calendar.chinese_lunar_calendar',
      'calendar.corresponding_lunar',
      'calendar.corresponding_solar',
      'unit.day',
    ]) {
      expect(source, contains("'$key'"), reason: key);
    }

    for (final hardcoded in [
      "'新增纪念'",
      "'编辑纪念'",
      "'添加'",
      "'保存'",
      "'标题'",
      "'如：妈妈生日 / 结婚纪念日'",
      "'备注 (可选)'",
      "'类型'",
      "'⏰ 倒数日'",
      "'🎂 生日'",
      "'💞 纪念日'",
      "'🔁 自定义'",
      "'日期类型'",
      "'选择日期'",
      "'公历和农历使用独立组件'",
      "'颜色标识'",
      "'到期提醒'",
      "'关闭'",
      "'提前天数:'",
      "'提醒时间'",
    ]) {
      expect(source, isNot(contains(hardcoded)), reason: hardcoded);
    }

    expect(
      RegExp(r'''['"][一-龥][^'"]*['"]''').hasMatch(source),
      isFalse,
      reason:
          'anniversary_screen.dart should not contain hardcoded Chinese UI strings',
    );
  });

  test('纪念日和生日提供独立入口页面，倒数日使用独立倒数页', () {
    final anniversary = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();

    expect(anniversary, contains('final AnniversaryType? fixedType;'));
    expect(
      anniversary,
      contains('class BirthdayScreen extends StatelessWidget'),
    );
    expect(
      anniversary,
      contains('class MemorialAnniversaryScreen extends StatelessWidget'),
    );
    expect(anniversary, contains('fixedType == null'));
    expect(
      anniversary,
      contains('final canAdd = fixedType != AnniversaryType.normal'),
    );
    expect(anniversary, contains('floatingActionButton: canAdd'));
    expect(
      anniversary,
      contains("actionLabel: onAdd == null ? null : I18n.tr('action.add')"),
    );
    expect(anniversary, contains('fixedType == AnniversaryType.normal'));
    expect(anniversary, contains("ValueKey('anniversary_fixed_\$name')"));
    expect(anniversary, contains('_tabs = TabController(length: 3'));
    expect(anniversary, contains('children: List.generate(3'));
    expect(mine, contains('child: anniversary.MemorialAnniversaryScreen()'));
    expect(mine, contains('child: anniversary.BirthdayScreen()'));
    expect(mine, contains('child: CountdownScreen()'));
    expect(mine, contains("label: I18n.tr('countdown.title')"));
    expect(mine, isNot(contains('const AnniversaryScreen(initialTab: 3)')));
    expect(
      anniversary,
      isNot(contains("Tab(text: I18n.tr('anniversary.countdown_short'))")),
    );
    expect(anniversary, isNot(contains('3 => AnniversaryType.normal')));
  });

  test('纪念日和生日二级页面使用紧凑统一样式', () {
    final source = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final routeBackground ='));
    expect(source, contains('backgroundColor: routeBackground'));
    expect(
      source,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(source, contains('surfaceTintColor: Colors.transparent'));
    expect(
      source,
      contains('backgroundColor: routeBackground.withValues(alpha: 0.96)'),
    );
    expect(source, contains('ColoredBox('));
    expect(source, contains('AppSecondaryControlTheme('));
    expect(source, contains('AppPageTabs('));
    expect(source, contains('height: AppPageTabs.heightFor(context)'));
    expect(source, contains("'anniversary_summary_total'"));
    expect(source, contains("'anniversary_summary_within_30_days'"));
    expect(source, contains('AppSectionHeader('));
    expect(source, contains("I18n.tr('countdown.nearest.prefix')"));
    expect(source, contains("I18n.tr('countdown.summary.total')"));
    expect(source, contains("'anniversary.summary.within_30_days'"));
    expect(source, contains("'anniversary.list.subtitle'"));
    expect(source, contains('appSecondaryRouteTitleTextStyle('));
  });

  test('生日和纪念日固定类型添加页不允许切换到其他类型', () {
    final source = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final editor = source.substring(
      source.indexOf('class _AnniversaryEditSheetState'),
      source.indexOf('class _AnniversaryReminderPreflightResult'),
    );

    expect(
      source,
      contains(
        'fixedType: widget.fixedType ?? _typeForTab ?? AnniversaryType.memorial',
      ),
    );
    expect(
      source,
      contains('_AnniversaryEditSheet(editing: item, fixedType: editorType)'),
    );
    expect(source, contains('fixedType == AnniversaryType.normal'));
    expect(source, contains('fixedType: item.type'));
    expect(editor, contains('final isTypeLocked = widget.fixedType != null'));
    expect(editor, contains('if (!isTypeLocked) ...['));
    expect(editor, contains('ChoiceChip('));
    expect(editor, contains('_type = e?.type ?? widget.fixedType'));
    expect(editor, contains('widget.editing != null ||'));
    expect(editor, contains('t != AnniversaryType.normal'));
  });

  test('生日和纪念日卡片使用轻量统一风格', () {
    final source = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final card = source.substring(
      source.indexOf('class _AnniversaryCard'),
      source.indexOf('class _AnniversaryEditSheet'),
    );

    expect(card, contains('AppSurfaceCard('));
    expect(card, contains('class _AnniversaryCard extends StatefulWidget'));
    expect(card, contains('onHorizontalDragUpdate'));
    expect(card, contains('Matrix4.translationValues(-_swipeOffset'));
    expect(card, contains('class _AnniversaryInlineSwipeActions'));
    expect(card, contains("ValueKey('anniversary_swipe_delete_button')"));
    expect(card, contains('appSecondaryRouteTitleTextStyle(context)'));
    expect(card, contains('appSecondaryControlLabelStyle('));
    expect(
      card,
      contains('Border.all(color: color.withValues(alpha: 0.12), width: 0.45)'),
    );
    expect(card, contains('BorderRadius.circular(14)'));
    expect(card, contains('width: 5'));
    expect(card, contains('fontSize: days == 0 ? 14 : 18'));
    expect(card, contains('fontSize: 11'));
    expect(card, isNot(contains('LinearGradient(')));
    expect(card, isNot(contains('IntrinsicHeight(')));
    expect(card, isNot(contains('Dismissible(')));
    expect(card, isNot(contains('onDismissed:')));
    expect(card, isNot(contains('fontSize: days == 0 ? 22 : 30')));
    expect(card, isNot(contains('textTheme.titleMedium')));
    expect(card, isNot(matches(RegExp(r'FontWeight\.(bold|w700|w800|w900)'))));
    for (final call in _calls(card, 'Border.all(')) {
      expect(call, contains('width: 0.45'), reason: call);
    }
  });

  test('纪念日提醒保存前检查通知权限和时间', () {
    final source = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final saveStart = source.indexOf('Future<void> _save() async');
    final saveEnd = source.indexOf('@override', saveStart);
    expect(saveStart, greaterThanOrEqualTo(0));
    expect(saveEnd, greaterThan(saveStart));
    final saveMethod = source.substring(saveStart, saveEnd);

    expect(
      source,
      contains("import '../providers/notification_service.dart';"),
    );
    expect(source, contains("import '../services/alarm_service.dart';"));
    expect(source, contains("import '../services/local_notifications.dart';"));
    expect(source, contains('Future<_AnniversaryReminderPreflightResult>'));
    expect(source, contains('ensureReadyForReminder('));
    expect(
      source,
      contains(
        "final issueTitle = I18n.tr('anniversary.reminder.register_failed')",
      ),
    );
    expect(source, contains('scheduledTime: remindAt'));
    expect(source, contains('case ReminderKind.push:'));
    expect(source, contains('case ReminderKind.popup:'));
    expect(source, contains('case ReminderKind.alarm:'));
    expect(source, contains('case ReminderKind.off:'));
    expect(source, contains('LocalNotifications.instance.ensurePermission()'));
    expect(source, contains('AlarmService.instance'));
    expect(source, contains('.notificationChannelIds()'));
    expect(source, contains('.hasExactAlarmPermission()'));
    expect(source, contains('.hasFullScreenIntentPermission()'));
    expect(source, contains('void _showSnackBarIfPossible'));
    expect(source, contains('Scaffold.maybeOf(context) == null'));
    expect(saveMethod, contains('_showSnackBarIfPossible('));
    expect(saveMethod, contains('ScaffoldMessenger.maybeOf(context)'));
    expect(
      saveMethod.indexOf('await _checkReminderBeforeSave('),
      lessThan(saveMethod.indexOf('await p.add(item)')),
    );
    final popIndex = saveMethod.indexOf('Navigator.pop(context)');
    expect(popIndex, greaterThan(saveMethod.indexOf('await p.add(item)')));
    expect(popIndex, greaterThan(saveMethod.indexOf('await p.update(item)')));
    expect(source, contains('reminderKind: remind ? kind : ReminderKind.off'));
    expect(source, contains('bool _saving = false'));
    expect(source, contains('if (_saving) return'));
    expect(source, contains('setState(() => _saving = true)'));
    expect(source, contains('onPressed: _saving ? null : _save'));
    expect(source, contains('CircularProgressIndicator(strokeWidth: 2)'));
    expect(source, isNot(contains('showAnniversaryEditor(routeContext')));
    expect(
      saveMethod,
      contains('_buildItem(remind: _remind, kind: _reminderKind)'),
    );
    expect(source, contains('value: ReminderKind.push'));
    expect(source, contains('value: ReminderKind.popup'));
    expect(source, contains('value: ReminderKind.alarm'));
    expect(source, contains('value: ReminderKind.off'));
  });

  test('生日编辑器把忽略年份开关写入纪念日模型', () {
    final source = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final editor = source.substring(
      source.indexOf('class _AnniversaryEditSheetState'),
      source.indexOf('class _AnniversaryReminderPreflightResult'),
    );

    expect(editor, contains('bool _ignoreYear = false'));
    expect(editor, contains('_ignoreYear = e?.ignoreYear ?? false'));
    expect(
      editor,
      contains(
        'ignoreYear: _type == AnniversaryType.birthday ? _ignoreYear : false',
      ),
    );
    expect(
      editor,
      contains('allowIgnoreYear: _type == AnniversaryType.birthday'),
    );
    expect(editor, contains('_ignoreYear = result.ignoreYear'));
  });
}

Iterable<String> _calls(String source, String token) sync* {
  var searchFrom = 0;
  while (true) {
    final start = source.indexOf(token, searchFrom);
    if (start == -1) return;
    var depth = 0;
    var end = start;
    for (; end < source.length; end++) {
      final char = source[end];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          end++;
          break;
        }
      }
    }
    yield source.substring(start, end);
    searchFrom = end;
  }
}
