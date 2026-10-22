import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('倒数日恢复可见入口、搜索、日历聚合、深链和提醒重排', () {
    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final search = File('lib/screens/search_screen.dart').readAsStringSync();
    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    final export = File('lib/screens/export_screen.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final provider = File(
      'lib/providers/countdown_provider.dart',
    ).readAsStringSync();

    expect(mine, contains("label: I18n.tr('countdown.title')"));
    expect(mine, contains('child: CountdownScreen()'));
    expect(moreApps, isNot(contains("label: '倒数日'")));
    expect(moreApps, isNot(contains('CountdownScreen')));
    expect(
      moreApps,
      isNot(contains('保留倒数日等独立入口')),
      reason: '倒数日保留在我的日程日期入口，不再由更多应用承载。',
    );

    final countdownScreen = File(
      'lib/screens/countdown_screen.dart',
    ).readAsStringSync();
    expect(
      countdownScreen,
      contains('class _CountdownCard extends StatefulWidget'),
    );
    expect(countdownScreen, contains('onHorizontalDragUpdate'));
    expect(
      countdownScreen,
      contains('Matrix4.translationValues(-_swipeOffset'),
    );
    expect(countdownScreen, contains('class _CountdownInlineSwipeActions'));
    expect(
      countdownScreen,
      contains("ValueKey('countdown_swipe_delete_button')"),
    );
    expect(countdownScreen, isNot(contains('Dismissible(')));
    expect(countdownScreen, isNot(contains('onDismissed:')));
    expect(countdownScreen, contains("I18n.tr('anniversary.delete.title')"));

    expect(search, contains('CountdownProvider'));
    expect(search, contains('CountdownScreen(initialCountdownId: h.sourceId)'));
    expect(
      search,
      contains('countdowns: context.read<CountdownProvider>().items'),
    );

    expect(calendar, contains('CountdownProvider'));
    expect(
      calendar,
      contains('final countdownProvider = context.watch<CountdownProvider>()'),
    );
    expect(calendar, contains('_countdownSignature(countdownProvider.items)'));
    expect(calendar, contains('countdowns: countdownProvider.items'));

    expect(export, contains('CountdownProvider'));
    expect(
      export,
      contains('countdowns: context.read<CountdownProvider>().items'),
    );

    expect(main, contains("uri.host == 'countdown'"));
    expect(
      main,
      contains("CalendarEventType.countdown => 'duoyi://countdown/\$id'"),
    );
    expect(main, contains('countdowns.items'));
    expect(main, isNot(contains('CalendarEventType.countdown => \'\'')));

    expect(
      provider,
      contains('Future<void> addItem(CountdownItem item) async'),
    );
    expect(provider, contains('_items.add(item)'));
    expect(provider, contains('await _syncRemindersNow()'));
  });

  test('倒数日可见主流程文档禁止回退为旧兼容模式', () {
    final requirementV2 = File('docs/requirement-v2.md').readAsStringSync();
    final designV2 = File('docs/design-v2.md').readAsStringSync();
    final taskV2 = File('docs/task-v2.md').readAsStringSync();

    for (final doc in [requirementV2, designV2, taskV2]) {
      expect(doc, contains('倒数日'));
      expect(doc, contains('新增'));
      expect(doc, contains('搜索'));
      expect(doc, contains('日历聚合'));
      expect(doc, contains('深链'));
      expect(doc, isNot(contains('倒数日旧数据兼容但不再作为可见主流程')));
      expect(doc, isNot(contains('不再暴露新增、搜索、日历聚合、通知深链')));
    }
  });

  test('倒数日与生日纪念日卡片保持同一套轻量布局契约', () {
    final countdown = File(
      'lib/screens/countdown_screen.dart',
    ).readAsStringSync();
    final anniversary = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final countdownCard = countdown.substring(
      countdown.indexOf('class _CountdownCard'),
      countdown.indexOf('class _StatusPill'),
    );
    final anniversaryCard = anniversary.substring(
      anniversary.indexOf('class _AnniversaryCard'),
      anniversary.indexOf('class _AnniversaryEditSheet'),
    );

    for (final card in [countdownCard, anniversaryCard]) {
      expect(card, contains('AppSurfaceCard('));
      expect(card, contains('appSecondaryRouteTitleTextStyle(context)'));
      expect(card, contains('appSecondaryControlLabelStyle('));
      expect(
        card,
        contains(
          'Border.all(color: color.withValues(alpha: 0.12), width: 0.45)',
        ),
      );
      expect(card, contains('BorderRadius.circular(14)'));
      expect(card, contains('width: 5'));
      expect(card, contains('onHorizontalDragUpdate'));
      expect(card, contains('Matrix4.translationValues(-_swipeOffset'));
      expect(card, contains('cs.errorContainer.withValues(alpha: 0.86)'));
      expect(card, contains('cs.onErrorContainer'));
      expect(card, isNot(contains('LinearGradient(')));
      expect(card, isNot(contains('Dismissible(')));
      expect(card, isNot(contains('onDismissed:')));
      expect(
        card,
        isNot(matches(RegExp(r'FontWeight\.(bold|w700|w800|w900)'))),
      );
    }

    expect(
      countdownCard,
      contains('crossAxisAlignment: WrapCrossAlignment.center'),
    );

    final countdownPillIndex = countdownCard.indexOf(
      '_StatusPill(label: status, color: color)',
    );
    final countdownTargetIndex = countdownCard.indexOf(
      "I18n.tr('countdown.target.prefix')",
    );
    final anniversaryPillIndex = anniversaryCard.indexOf(
      '_AnniversaryPill(label: _typeLabel(), color: color)',
    );
    final anniversaryNextIndex = anniversaryCard.indexOf(
      "I18n.tr('anniversary.next.prefix')",
    );

    expect(countdownPillIndex, isNot(-1));
    expect(countdownTargetIndex, isNot(-1));
    expect(anniversaryPillIndex, isNot(-1));
    expect(anniversaryNextIndex, isNot(-1));
    expect(
      countdownTargetIndex,
      greaterThan(countdownPillIndex),
      reason: '倒数日卡片应和生日/纪念日一样，先展示类型/状态标签，再展示日期元信息。',
    );
    expect(
      anniversaryNextIndex,
      greaterThan(anniversaryPillIndex),
      reason: '生日/纪念日卡片的元信息顺序是统一样式的基准。',
    );
    expect(
      countdownCard.indexOf('const SizedBox(width: 12)'),
      greaterThan(countdownTargetIndex),
      reason: '倒数日目标日期应留在左侧信息列，避免和右侧天数指标混排。',
    );
  });

  test('纪念日编辑器删除复用确认弹窗', () {
    final source = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final editSheet = source.substring(
      source.indexOf('class _AnniversaryEditSheetState'),
      source.indexOf('class _AnniversaryReminderPreflightResult'),
    );
    final leadingStart = editSheet.indexOf(
      'leadingActions: widget.editing == null',
    );
    expect(
      leadingStart,
      greaterThanOrEqualTo(0),
      reason: '纪念日编辑器的删除入口应留在 leadingActions。',
    );
    final actionsStart = editSheet.indexOf('actions: [', leadingStart);
    expect(
      actionsStart,
      greaterThan(leadingStart),
      reason: '删除入口必须位于底部 actions 之前，缩进随 dart format 变化，不写死空格数。',
    );
    final leadingDelete = editSheet.substring(leadingStart, actionsStart);

    expect(editSheet, contains('Future<void> _delete() async'));
    expect(editSheet, contains('showDialog<bool>'));
    expect(editSheet, contains("I18n.tr('anniversary.delete.title')"));
    expect(editSheet, contains("I18n.tr('anniversary.delete.content_suffix')"));
    expect(leadingDelete, contains('onPressed: _delete'));
    expect(
      leadingDelete,
      isNot(contains('context.read<AnniversaryProvider>().delete')),
    );
  });
}
