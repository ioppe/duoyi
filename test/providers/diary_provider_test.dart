import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  DiaryEntry entry(String id, DateTime date, {String content = ''}) =>
      DiaryEntry(id: id, date: date, content: content);

  group('DiaryProvider.entries 排序缓存', () {
    test('a) 乱序插入后 entries 为日期倒序，且连续多次访问结果一致', () async {
      final provider = DiaryProvider();
      await provider.addOrUpdate(entry('b', DateTime(2026, 1, 1)));
      await provider.addOrUpdate(entry('c', DateTime(2026, 1, 2)));
      await provider.addOrUpdate(entry('a', DateTime(2026, 1, 3)));

      final first = provider.entries.map((e) => e.id).toList();
      final second = provider.entries.map((e) => e.id).toList();
      final third = provider.entries.map((e) => e.id).toList();

      expect(first, ['a', 'c', 'b'], reason: '应按 date 倒序');
      expect(second, first, reason: '连续访问结果应一致');
      expect(third, first, reason: '连续访问结果应一致');
    });

    test('b1) 删除后缓存失效并重排', () async {
      final provider = DiaryProvider();
      await provider.addOrUpdate(entry('a', DateTime(2026, 1, 3)));
      await provider.addOrUpdate(entry('c', DateTime(2026, 1, 2)));
      await provider.addOrUpdate(entry('b', DateTime(2026, 1, 1)));
      expect(provider.entries.map((e) => e.id), ['a', 'c', 'b']);

      await provider.delete('c');

      expect(provider.entries.map((e) => e.id), [
        'a',
        'b',
      ], reason: '删除后应重排，不能返回失效缓存');
      expect(provider.totalCount, 2);
    });

    test('b2) 同 id 更新日期后缓存失效并重排', () async {
      final provider = DiaryProvider();
      await provider.addOrUpdate(entry('b', DateTime(2026, 1, 1)));
      await provider.addOrUpdate(entry('a', DateTime(2026, 1, 3)));
      expect(provider.entries.map((e) => e.id), ['a', 'b']);

      // 同 id、日期改到更晚 → 替换分支 → 排序键变化。
      await provider.addOrUpdate(
        entry('b', DateTime(2026, 1, 5), content: 'moved'),
      );

      expect(provider.entries.map((e) => e.id), [
        'b',
        'a',
      ], reason: '更新日期后应重排，不能返回失效缓存');
    });

    test('b3) 同一天不同 id 走合并分支：条数不变且顺序稳定', () async {
      final provider = DiaryProvider();
      await provider.addOrUpdate(
        entry('a', DateTime(2026, 1, 3), content: 'v1'),
      );

      await provider.addOrUpdate(
        entry('a2', DateTime(2026, 1, 3), content: 'v2'),
      );

      expect(provider.totalCount, 1);
      expect(provider.entries.map((e) => e.id), ['a']);
      expect(provider.entries.single.content, 'v2', reason: '同日合并应覆盖内容');
    });

    test('c) 读取 entries 不变异内部列表顺序（持久化顺序保持插入序）', () async {
      final provider = DiaryProvider();
      await provider.addOrUpdate(entry('b', DateTime(2026, 1, 1)));
      await provider.addOrUpdate(entry('c', DateTime(2026, 1, 2)));
      await provider.addOrUpdate(entry('a', DateTime(2026, 1, 3)));

      // 旧实现会在读取时就地排序内部列表（变异为倒序 [a, c, b]）。
      provider.entries;
      provider.entries;

      // 同 id 更新（日期不变）触发重写持久化，把当前内部顺序落盘。
      await provider.addOrUpdate(
        entry('b', DateTime(2026, 1, 1), content: 'b2'),
      );

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('duoyi_diary')!;
      final storedIds = stored
          .map(
            (raw) =>
                DiaryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>).id,
          )
          .toList();
      // 内部顺序应保持插入序 [b, c, a]；若读取发生了变异，此处会是 [a, c, b]。
      expect(storedIds, ['b', 'c', 'a']);
    });

    test('loadFromStorage 后缓存失效（云同步回写场景）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_diary': <String>[
          jsonEncode(entry('e-old', DateTime(2026, 1, 1)).toJson()),
        ],
      });
      final provider = DiaryProvider();
      await provider.loadFromStorage();
      expect(provider.entries.map((e) => e.id), ['e-old']);

      // 模拟云同步回写：直接改持久层再 load。
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('duoyi_diary', <String>[
        jsonEncode(entry('e-old', DateTime(2026, 1, 1)).toJson()),
        jsonEncode(entry('e-new2', DateTime(2026, 1, 2)).toJson()),
        jsonEncode(entry('e-new3', DateTime(2026, 1, 3)).toJson()),
      ]);
      await provider.loadFromStorage();

      expect(provider.entries.map((e) => e.id), [
        'e-new3',
        'e-new2',
        'e-old',
      ], reason: '重新加载后应按新数据倒序，不能返回旧缓存');
    });

    test('resetLocalState 后 entries 为空', () async {
      final provider = DiaryProvider();
      await provider.addOrUpdate(entry('a', DateTime(2026, 1, 3)));
      expect(provider.entries, isNotEmpty);

      provider.resetLocalState();

      expect(provider.entries, isEmpty);
      expect(provider.totalCount, 0);
    });
  });

  group('DiaryScreen retired compatibility route', () {
    testWidgets('historical records remain cached without building any cards', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = DiaryProvider();
      const total = 60;
      final base = DateTime(2026, 1, 28);
      for (var i = 0; i < total; i++) {
        await provider.addOrUpdate(
          entry(
            'entry-$i',
            base.subtract(Duration(days: i)),
            content: 'day $i',
          ),
        );
      }

      await tester.pumpWidget(
        ChangeNotifierProvider<DiaryProvider>.value(
          value: provider,
          child: const MaterialApp(home: DiaryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(I18n.tr('feature.unavailable')), findsWidgets);
      expect(find.text(I18n.tr('diary.summary.title')), findsNothing);
      expect(find.byKey(const ValueKey('diary_card_entry-0')), findsNothing);
      expect(
        find.byKey(const ValueKey('diary_card_entry-${total - 1}')),
        findsNothing,
      );
      // 构建出的卡片数量应远小于总数。
      final builtCards = find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.startsWith(
                  'diary_card_',
                ),
          )
          .evaluate()
          .length;
      expect(builtCards, 0);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(provider.entries, hasLength(total));
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  });
}
