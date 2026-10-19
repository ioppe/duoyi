import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('retired route follows theme without exposing mood reports', () {
    final source = File('lib/screens/diary_screen.dart').readAsStringSync();
    expect(source, contains('Brightness.dark'));
    expect(source, contains('cs.surfaceContainerLowest'));
    expect(source, contains('backgroundColor: routeBackground'));
    expect(source, isNot(contains('_showMoodStats')));
    expect(source, isNot(contains('moodDistribution')));
    expect(source, isNot(contains('Colors.grey')));
  });
}
