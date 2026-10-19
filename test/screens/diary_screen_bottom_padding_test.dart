import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final editing in [false, true]) {
    testWidgets(
      'legacy route (editing: $editing) leaves stored records untouched',
      (tester) async {
        final entry = DiaryEntry(
          date: DateTime(2026, 10, 3),
          content: 'private historical content',
        );
        final provider = DiaryProvider();
        await provider.addOrUpdate(entry);
        final prefs = await SharedPreferences.getInstance();
        final before = prefs.getStringList('duoyi_diary');
        await tester.pumpWidget(
          ChangeNotifierProvider<DiaryProvider>.value(
            value: provider,
            child: MaterialApp(
              home: editing
                  ? DiaryEditScreen(entry: entry)
                  : const DiaryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(I18n.tr('feature.unavailable')), findsWidgets);
        expect(find.text(entry.content), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(provider.entries.single.id, entry.id);
        expect(prefs.getStringList('duoyi_diary'), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      },
    );
  }
}
