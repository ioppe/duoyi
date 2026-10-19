import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'retired route uses generic localized feedback without promoting editing',
    () {
      final source = File('lib/screens/diary_screen.dart').readAsStringSync();
      expect(source, contains("I18n.tr('feature.unavailable')"));
      expect(source, isNot(contains("I18n.tr('diary.")));
      expect(source, isNot(contains('TextField(')));
      expect(source, isNot(contains('FloatingActionButton')));
      expect(source, isNot(contains('DiaryProvider')));
      expect(source, isNot(contains('addOrUpdate')));
      expect(source, isNot(contains('.delete(')));
    },
  );
}
