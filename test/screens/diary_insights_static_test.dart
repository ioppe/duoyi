import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('retired UI cannot open insights or AI review', () {
    final screen = File('lib/screens/diary_screen.dart').readAsStringSync();
    expect(screen, isNot(contains('DiaryInsightEngine')));
    expect(screen, isNot(contains('AiService')));
    expect(screen, isNot(contains('deepDiaryReview')));
    expect(screen, isNot(contains('MoodHeatmap')));
  });

  test(
    'historical review helpers remain compatible without UI entry points',
    () {
      final service = File('lib/services/ai_service.dart').readAsStringSync();
      expect(service, contains("import '../core/diary_deep_review.dart';"));
      expect(service, contains('Future<String> deepDiaryReview('));
      expect(service, contains('DiaryDeepReviewBuilder.build('));
      expect(service, contains('maxTokens: 900'));
    },
  );
}
