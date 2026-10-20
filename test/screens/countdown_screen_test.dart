import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('empty countdown page exposes add entry and creates countdown', (
    tester,
  ) async {
    final provider = CountdownProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: CountdownScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无倒数日记录'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown_add_button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('countdown_add_button')),
        matching: find.text('添加'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('countdown_add_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '版本发布');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('countdown_editor_save_button')),
    );
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '版本发布');
    expect(find.text('倒数日已保存'), findsOneWidget);
    expect(find.text('暂无倒数日记录'), findsNothing);
    expect(find.text('全部倒数日'), findsOneWidget);
    expect(find.text('版本发布'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('countdown_swipe_delete_button')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('countdown_card_${provider.items.single.id}')),
      findsOneWidget,
    );
  });

  testWidgets('more applications does not expose countdown entry', (
    tester,
  ) async {
    final provider = CountdownProvider();
    await provider.loadFromStorage();
    final preferences = PreferencesProvider();
    final theme = ThemeProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider.value(value: preferences),
          ChangeNotifierProvider.value(value: theme),
        ],
        child: const MaterialApp(
          home: MoreApplicationsScreen(visibleBottomNavTabs: [0, 1, 2, 3, 6]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MoreApplicationsScreen), findsOneWidget);
    expect(find.text('倒数日'), findsNothing);
    expect(provider.items, isEmpty);
  });

  testWidgets('deleting countdown refreshes header totals immediately', (
    tester,
  ) async {
    final provider = CountdownProvider();
    await provider.loadFromStorage();
    final today = DateTime.now();
    final soon = CountdownItem(
      id: 'soon-countdown',
      title: '近期事项',
      targetDate: DateTime(
        today.year,
        today.month,
        today.day,
      ).add(const Duration(days: 3)),
    );
    final later = CountdownItem(
      id: 'later-countdown',
      title: '远期事项',
      targetDate: DateTime(
        today.year,
        today.month,
        today.day,
      ).add(const Duration(days: 20)),
    );
    await provider.addItem(soon);
    await provider.addItem(later);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: CountdownScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final total = find.byKey(const ValueKey('countdown_summary_total'));
    final within7 = find.byKey(
      const ValueKey('countdown_summary_within_7_days'),
    );
    expect(
      find.descendant(of: total, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: within7, matching: find.text('1')),
      findsOneWidget,
    );

    await provider.deleteItem(soon.id);
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(find.text('近期事项'), findsNothing);
    expect(find.text('远期事项'), findsOneWidget);
    expect(
      find.descendant(of: total, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: within7, matching: find.text('0')),
      findsOneWidget,
    );
  });

  testWidgets(
    'countdown page keeps summary reminder controls and long pills readable at 320px',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      final today = DateTime.now();
      const longCategory = '特别特别特别长的分类名称用于验证窄屏标签不会溢出';
      SharedPreferences.setMockInitialValues({
        'duoyi_countdowns': [
          jsonEncode(
            CountdownItem(
              id: 'narrow-countdown',
              title: '窄屏测试事项',
              targetDate: DateTime(
                today.year,
                today.month,
                today.day,
              ).add(const Duration(days: 2)),
              category: longCategory,
              remind: true,
              remindDaysBefore: 1,
              remindHour: 9,
              remindMinute: 30,
            ).toJson(),
          ),
        ],
      });

      final provider = CountdownProvider();
      await provider.loadFromStorage();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(home: CountdownScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('countdown_summary_total')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('countdown_summary_within_7_days')),
        findsOneWidget,
      );
      expect(find.text('窄屏测试事项'), findsOneWidget);
      expect(find.text(longCategory), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('窄屏测试事项'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('countdown_reminder_kind_scroll')),
        findsOneWidget,
      );
      expect(find.text('通知'), findsOneWidget);
      expect(find.text('弹出框'), findsOneWidget);
      expect(find.text('闹钟'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'birthday memorial and countdown cards keep a consistent surface style',
    () {
      final countdownSource = File(
        'lib/screens/countdown_screen.dart',
      ).readAsStringSync();
      final anniversarySource = File(
        'lib/screens/anniversary_screen.dart',
      ).readAsStringSync();
      final countdownCard = countdownSource.substring(
        countdownSource.indexOf('class _CountdownCard'),
        countdownSource.indexOf('class _CountdownInlineSwipeActions'),
      );
      final anniversaryCard = anniversarySource.substring(
        anniversarySource.indexOf('class _AnniversaryCard'),
        anniversarySource.indexOf('class _AnniversaryInlineSwipeActions'),
      );

      for (final card in [countdownCard, anniversaryCard]) {
        expect(card, contains('child: AppSurfaceCard('));
        expect(card, contains('margin: const EdgeInsets.only(bottom: 12)'));
        expect(card, contains('padding: EdgeInsets.zero'));
        expect(card, contains('borderRadius: BorderRadius.circular(14)'));
        expect(
          card,
          contains(
            'Border.all(color: color.withValues(alpha: 0.12), width: 0.45)',
          ),
        );
        expect(card, contains('width: 5'));
        expect(
          card,
          contains('padding: const EdgeInsets.fromLTRB(14, 12, 12, 12)'),
        );
        expect(card, contains('Wrap('));
        expect(card, contains('constraints: const BoxConstraints('));
        expect(card, contains('minWidth: 54'));
        expect(card, contains('maxWidth: 108'));
        expect(card, contains('TextBaseline.alphabetic'));
        expect(
          card,
          anyOf(
            contains('fontSize: 18'),
            contains('fontSize: days == 0 ? 14 : 18'),
          ),
        );
        expect(card, contains('fontWeight: DesignTokens.fontWeightStrong'));
        expect(card, contains('AnimatedContainer('));
        expect(
          card,
          contains('Matrix4.translationValues(-_swipeOffset, 0, 0)'),
        );
      }

      expect(
        countdownSource,
        contains("ValueKey('countdown_card_\${item.id}')"),
      );
      expect(
        anniversarySource,
        contains("ValueKey('anniversary_card_\${item.id}')"),
      );
      expect(
        anniversaryCard,
        contains(
          "AnniversaryType.birthday => '🎂 \${I18n.tr('anniversary.birthday')}'",
        ),
      );
      expect(
        anniversaryCard,
        contains(
          "AnniversaryType.memorial => '💞 \${I18n.tr('anniversary.title')}'",
        ),
      );
    },
  );

  testWidgets(
    'countdown list handles 320 390 430 and desktop widths without overflow',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final today = DateTime.now();
      const longCategory = '特别特别特别长的分类名称用于验证宽度变化时标签仍然省略';
      const longTitle = '这是一个非常长的倒数日标题用于验证列表卡片不会遮挡右侧天数';
      SharedPreferences.setMockInitialValues({
        'duoyi_countdowns': [
          jsonEncode(
            CountdownItem(
              id: 'responsive-countdown',
              title: longTitle,
              targetDate: DateTime(
                today.year,
                today.month,
                today.day,
              ).add(const Duration(days: 12000)),
              category: longCategory,
              remind: true,
              remindDaysBefore: 30,
              remindHour: 23,
              remindMinute: 55,
            ).toJson(),
          ),
        ],
      });
      final provider = CountdownProvider();
      await provider.loadFromStorage();

      for (final size in const [
        Size(320, 720),
        Size(390, 720),
        Size(430, 720),
        Size(1024, 768),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: const MaterialApp(home: CountdownScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(longTitle), findsOneWidget);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('countdown_summary_total')))
              .right,
          lessThanOrEqualTo(size.width),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('existing countdown can still be edited', (tester) async {
    SharedPreferences.setMockInitialValues({
      'duoyi_countdowns': [
        jsonEncode({
          'id': 'release',
          'title': '版本发布',
          'targetDate': '2026-06-01T00:00:00.000',
        }),
      ],
    });

    final provider = CountdownProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: CountdownScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('版本发布'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '版本补丁发布');
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('countdown_editor_save_button')),
    );
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '版本补丁发布');
    expect(find.text('版本补丁发布'), findsOneWidget);
  });

  testWidgets(
    'existing countdown left swipe reveals delete action and confirms',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'duoyi_countdowns': [
          jsonEncode({
            'id': 'release',
            'title': '版本发布',
            'targetDate': '2026-06-01T00:00:00.000',
          }),
        ],
      });

      final provider = CountdownProvider();
      await provider.loadFromStorage();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(home: CountdownScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('版本发布'), findsOneWidget);

      await tester.drag(find.text('版本发布'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(provider.items, hasLength(1));
      expect(
        find.byKey(const ValueKey('countdown_swipe_delete_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('countdown_swipe_delete_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('确认删除？'), findsOneWidget);
      expect(provider.items, hasLength(1));

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(provider.items, isEmpty);
      expect(find.text('版本发布'), findsNothing);
      expect(find.text('暂无倒数日记录'), findsOneWidget);
    },
  );

  testWidgets('existing countdown can be deleted from editor', (tester) async {
    SharedPreferences.setMockInitialValues({
      'duoyi_countdowns': [
        jsonEncode({
          'id': 'release',
          'title': '版本发布',
          'targetDate': '2026-06-01T00:00:00.000',
        }),
      ],
    });

    final provider = CountdownProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: CountdownScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('版本发布'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('确认删除？'), findsOneWidget);
    expect(provider.items, hasLength(1));

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(provider.items, isEmpty);
    expect(find.text('版本发布'), findsNothing);
    expect(find.text('暂无倒数日记录'), findsOneWidget);
  });

  testWidgets('fixed countdown anniversary page has no add entry', (
    tester,
  ) async {
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: AnniversaryScreen(fixedType: AnniversaryType.normal),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('添加'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(provider.items, isEmpty);
  });

  testWidgets('BirthdayScreen add creates birthday anniversary', (
    tester,
  ) async {
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: BirthdayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BirthdayScreen), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('天气'), findsNothing);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '测试生日');
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('anniversary_editor_save_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加').last);
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '测试生日');
    expect(provider.items.single.type, AnniversaryType.birthday);
    expect(provider.birthdays, hasLength(1));
    expect(provider.memorials, isEmpty);
    expect(provider.countdowns, isEmpty);
    expect(find.widgetWithText(FilledButton, '添加'), findsNothing);
    expect(find.text('测试生日'), findsOneWidget);
    expect(find.text('还没有任何纪念'), findsNothing);
  });

  testWidgets('MemorialAnniversaryScreen add creates memorial anniversary', (
    tester,
  ) async {
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: MemorialAnniversaryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MemorialAnniversaryScreen), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('天气'), findsNothing);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '测试纪念日');
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('anniversary_editor_save_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加').last);
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.title, '测试纪念日');
    expect(provider.items.single.type, AnniversaryType.memorial);
    expect(provider.birthdays, isEmpty);
    expect(provider.memorials, hasLength(1));
    expect(provider.countdowns, isEmpty);
    expect(find.widgetWithText(FilledButton, '添加'), findsNothing);
    expect(find.text('测试纪念日'), findsOneWidget);
    expect(find.text('还没有任何纪念'), findsNothing);
  });

  testWidgets('anniversary card left swipe reveals matching delete action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'duoyi_anniversaries_v2': [
        jsonEncode(
          Anniversary(
            id: 'birthday',
            title: '生日提醒',
            originDate: DateTime(2026, 7, 1),
            type: AnniversaryType.birthday,
          ).toJson(),
        ),
      ],
    });

    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: AnniversaryScreen(fixedType: AnniversaryType.birthday),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('生日提醒'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('anniversary_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('生日提醒'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(
      find.byKey(const ValueKey('anniversary_swipe_delete_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('anniversary_swipe_delete_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('确认删除？'), findsOneWidget);
    expect(provider.items, hasLength(1));

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(provider.items, isEmpty);
    expect(find.text('生日提醒'), findsNothing);
    expect(find.text('还没有任何纪念'), findsOneWidget);
  });

  testWidgets('direct normal anniversary editor creates memorial instead', (
    tester,
  ) async {
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAnniversaryEditor(
                context,
                fixedType: AnniversaryType.normal,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('倒数日'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '不会新增倒数日');
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('anniversary_editor_save_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.type, AnniversaryType.memorial);
    expect(provider.countdowns, isEmpty);
  });
}
