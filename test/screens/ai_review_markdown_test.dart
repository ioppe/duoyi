import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/ai_history_screen.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _review = '''**总判断：先恢复真实记录。 **

### 本周解读
只记录**明确的小事**，保留 `10 分钟` 的起点。

- **待办｜保留轻量。 ** 从一件小事开始。
- **专注**：短时开始。

### 未来 7 天
1. 写下下一步。
2. 保存一次专注。
''';

AiService _service() => AiService()
  ..attachClient(
    ApiClient(
      baseUrl: 'https://test.example',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/ai/chat');
        return http.Response.bytes(
          utf8.encode(jsonEncode({'content': _review})),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  )
  ..updateFromServerConfig({'ai_enabled': true, 'ai_model': 'test-model'});

Widget _app(AiService ai, Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AiService>.value(value: ai),
    ChangeNotifierProvider(create: (_) => TodoProvider()),
    ChangeNotifierProvider(create: (_) => GoalProvider()),
    ChangeNotifierProvider(create: (_) => HabitProvider()),
    ChangeNotifierProvider(create: (_) => PomodoroProvider()),
    ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
  ],
  child: MaterialApp(theme: AppBrands.defaultBrand.theme, home: home),
);

String _renderedText(Finder scope) => find
    .descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) => widget is RichText || widget is SelectableText,
      ),
    )
    .evaluate()
    .map((element) {
      final widget = element.widget;
      return widget is SelectableText
          ? widget.data ?? widget.textSpan!.toPlainText()
          : (widget as RichText).text.toPlainText();
    })
    .join('\n');

void _expectMarkdownRendered(Finder scope) {
  final text = _renderedText(scope);
  expect(text, contains('本周解读'));
  expect(text, contains('总判断：先恢复真实记录。'));
  expect(text, contains('待办｜保留轻量。'));
  expect(text, contains('写下下一步。'));
  expect(text, isNot(contains('###')));
  expect(text, isNot(contains('**')), reason: '同时兼容模型在粗体结尾加入空格的回复');
  expect(text, isNot(contains('`10 分钟`')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'statistics AI review renders Markdown and opens rendered history',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ai = _service();
      await tester.pumpWidget(_app(ai, const StatisticsScreen()));
      await tester.pumpAndSettle();
      final reviewButton = find.text('AI 解读');
      await tester.ensureVisible(reviewButton);
      await tester.tap(reviewButton);
      await tester.pumpAndSettle();
      expect(
        ai.reviewHistory,
        isNotEmpty,
        reason: _renderedText(find.byType(StatisticsScreen)),
      );
      expect(
        ai.reviewHistory.single.content,
        _review.trim(),
        reason: 'AiService 会 trim 新回复，历史记录保存的是去除首尾空白后的正文。',
      );
      expect(find.text('云端个性化解读'), findsOneWidget);
      _expectMarkdownRendered(find.byType(StatisticsScreen));
      await tester.ensureVisible(find.text('AI 历史'));
      await tester.tap(find.text('AI 历史'));
      await tester.pumpAndSettle();
      expect(find.byType(AiHistoryScreen), findsOneWidget);
      final toggle = find.byKey(
        ValueKey('ai_history_toggle_${ai.reviewHistory.single.id}'),
      );
      expect(find.text('本周解读', findRichText: true), findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      _expectMarkdownRendered(find.byType(AiHistoryScreen));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('本周解读', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      ai.dispose();
    },
  );

  testWidgets(
    'existing AI history renders without changing its copied source',
    (tester) async {
      final entry = AiReviewEntry(
        id: 'existing-review',
        createdAt: DateTime(2026, 10, 21),
        content: _review,
        summary: '统计报告 AI 解读：本周周报',
        model: 'test-model',
      );
      SharedPreferences.setMockInitialValues({
        'ai_review_history': [jsonEncode(entry.toJson())],
      });
      final ai = AiService();
      await ai.loadFromStorage();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      await tester.pumpWidget(_app(ai, const AiHistoryScreen()));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ai_history_toggle_existing-review')),
      );
      await tester.pumpAndSettle();
      _expectMarkdownRendered(find.byType(AiHistoryScreen));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(I18n.tr('ai_history.copy')));
      await tester.pumpAndSettle();
      expect(copied, _review);
      expect(ai.reviewHistory.single.content, _review);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      ai.dispose();
    },
  );
}
