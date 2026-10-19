import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';

void main() {
  test('通知设置铃声和音量控制在窄屏下仍保持同行紧凑布局', () {
    final source = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final sectionStart = source.indexOf('class _NotificationRingtoneSection');
    final sectionEnd = source.indexOf('class _ReportReminderSection');
    expect(sectionStart, greaterThanOrEqualTo(0));
    expect(sectionEnd, greaterThan(sectionStart));
    final section = source.substring(sectionStart, sectionEnd);

    expect(section, contains('class _RingtoneControlTile'));
    expect(section, contains('class _RingtoneSoundControl'));
    expect(section, contains('class _RingtoneVolumeControl'));
    expect(section, contains('availableWidth < 360'));
    expect(section, contains('width: controlWidth'));
    expect(section, contains('height: 34'));
    expect(section, contains('alignment: Alignment.centerRight'));
    expect(section, contains('return Row('));
    expect(section, isNot(contains('return Column(')));
    expect(
      section,
      contains("ValueKey('notification_ringtone_sound_control')"),
    );
    expect(
      section,
      contains("ValueKey('notification_ringtone_volume_control')"),
    );
    expect(section, isNot(contains('trailing: Row(')));
    expect(section, isNot(contains('trailing: Wrap(')));
  });

  test('检查更新弹窗安装包名使用可换行信息块', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();

    expect(source, contains('class _UpdatePackageInfo'));
    expect(source, contains('_breakableUpdateAssetName'));
    expect(source, contains('softWrap: true'));
    // 安装包标签已迁移 I18n（key 语义与旧字面量一致）。
    expect(source, contains("I18n.tr('mine.update.package_label')"));
    expect(source, isNot(contains("'安装包：\${updater.latestAssetName}'")));
  });

  test('强制更新信息行长值支持 320px 换行展示', () {
    final source = File(
      'lib/widgets/force_update_gate.dart',
    ).readAsStringSync();

    expect(source, contains('class _ForceUpdateInfoRow'));
    expect(source, contains('_breakableUpdateValue'));
    expect(source, contains('constraints.maxWidth < 300'));
    expect(source, contains('softWrap: true'));
    expect(source, contains("'安装包'"));
  });

  test('通知记录批量已读和筛选控件在窄屏下不挤压标题区', () {
    final source = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final appBarStart = source.indexOf('appBar: AppBar(');
    final appBarEnd = source.indexOf(
      'body: AppSecondaryControlTheme',
      appBarStart,
    );
    expect(appBarStart, greaterThanOrEqualTo(0));
    expect(appBarEnd, greaterThan(appBarStart));
    final appBar = source.substring(appBarStart, appBarEnd);

    expect(
      appBar,
      contains("ValueKey('notification_history_mark_all_read_button')"),
    );
    expect(appBar, contains("tooltip: '全部标为已读'"));
    expect(appBar, isNot(contains('TextButton.icon(')));

    final filterStart = source.indexOf('class _NotificationHistoryFilters');
    final filterEnd = source.indexOf('class _NotificationRecordCard');
    expect(filterStart, greaterThanOrEqualTo(0));
    expect(filterEnd, greaterThan(filterStart));
    final filters = source.substring(filterStart, filterEnd);
    expect(filters, contains('SegmentedButton<_NotificationReadFilter>'));
    expect(filters, contains('showSelectedIcon: false'));
    expect(filters, contains('scrollDirection: Axis.horizontal'));
  });

  test('退出登录确认明确提示本机账号数据清理', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();
    final logoutStart = source.indexOf('Future<void> _confirmLogout');
    final logoutEnd = source.indexOf(
      'Future<void> _pickAndSaveAvatar',
      logoutStart,
    );
    expect(logoutStart, greaterThanOrEqualTo(0));
    expect(logoutEnd, greaterThan(logoutStart));
    final logout = source.substring(logoutStart, logoutEnd);

    // 退出登录文案迁移 I18n：确认弹窗仍明确提示本机数据清理（key 语义）。
    expect(logout, contains("I18n.tr('mine.logout.confirm_content')"));
    expect(logout, contains("I18n.tr('mine.logout.done')"));
    expect(logout, contains("I18n.tr('mine.logout.cleanup_failed')"));
    expect(
      I18n.tr('mine.logout.confirm_content'),
      contains('主题、习惯、待办'),
      reason: '退出确认必须列出会被清空的账号数据类型',
    );
    expect(I18n.tr('mine.logout.confirm_content'), isNot(contains('时光币')));
    expect(I18n.tr('mine.logout.done'), contains('本机账号数据已清理'));
    expect(
      I18n.tr('mine.logout.cleanup_failed'),
      contains('本机数据清理失败，将在下次登录前重试'),
    );
  });
}
