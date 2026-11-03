import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/server_config_status.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({required AiService ai, AuthProvider? auth}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AiService>.value(value: ai),
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      if (auth != null) ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ],
    child: const MaterialApp(home: StatisticsScreen()),
  );
}

/// 首帧后还有异步配置请求：逐帧推进，避免停在不确定进度动画上超时。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

TextButton _aiButton(WidgetTester tester, String label) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, label).first);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('配置未知：显示细加载提示，不冒充管理员关闭', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ai = AiService();
    await tester.pumpWidget(_app(ai: ai));
    await _settle(tester);

    expect(ai.configStatus, ServerConfigStatus.unknown);
    expect(
      find.text(I18n.tr('statistics.ai.config.loading')),
      findsOneWidget,
      reason: '未加载完配置时只能显示加载中',
    );
    expect(
      find.text(I18n.tr('statistics.ai.disabled_hint')),
      findsNothing,
      reason: '不能把 unknown 当成管理员关闭',
    );
    expect(
      _aiButton(tester, I18n.tr('statistics.ai.generate')).onPressed,
      isNull,
      reason: '非 ready 不允许发新请求',
    );
  });

  testWidgets('配置加载中：不显示管理员关闭提示', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ai = AiService()
      ..updateServerConfigStatus(ServerConfigStatus.loading);
    await tester.pumpWidget(_app(ai: ai));
    await _settle(tester);

    expect(find.text(I18n.tr('statistics.ai.config.loading')), findsOneWidget);
    expect(find.text(I18n.tr('statistics.ai.disabled_hint')), findsNothing);
  });

  testWidgets('配置失败：显示失败与重试，重试成功后恢复可用', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var configRequests = 0;
    var failConfig = true;
    final auth = AuthProvider(
      baseUrl: 'https://cfg.test',
      client: ApiClient(
        baseUrl: 'https://cfg.test',
        httpClient: MockClient((request) async {
          configRequests++;
          if (failConfig) return http.Response('offline', 503);
          return http.Response(
            jsonEncode({'ai_enabled': true, 'ai_model': 'cfg-model'}),
            200,
          );
        }),
      ),
    );
    final ai = AiService();
    // 与 main.dart 相同的接线方式。
    auth.onServerConfigChanged = ai.updateFromServerConfig;
    auth.onServerConfigStatusChanged = ai.updateServerConfigStatus;

    await tester.pumpWidget(_app(ai: ai, auth: auth));
    await _settle(tester);

    expect(configRequests, 1, reason: '进入统计页应补一次配置请求');
    expect(ai.configStatus, ServerConfigStatus.failed);
    expect(find.text(I18n.tr('statistics.ai.config.failed')), findsOneWidget);
    expect(find.text(I18n.tr('statistics.ai.disabled_hint')), findsNothing);
    expect(find.text(I18n.tr('statistics.ai.config.loading')), findsNothing);

    failConfig = false;
    final retry = find.widgetWithText(
      TextButton,
      I18n.tr('statistics.ai.config.retry'),
    );
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await _settle(tester);

    expect(configRequests, 2, reason: '重试必须重新发请求');
    expect(ai.configStatus, ServerConfigStatus.ready);
    expect(ai.enabled, isTrue);
    expect(find.text(I18n.tr('statistics.ai.config.failed')), findsNothing);
    expect(
      _aiButton(tester, I18n.tr('statistics.ai.generate')).onPressed,
      isNotNull,
    );
  });

  testWidgets('真正禁用：ready 且管理员关闭时才显示原提示', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ai = AiService()
      ..updateFromServerConfig(const {
        'ai_enabled': false,
        'backup_enabled': true,
      });
    await tester.pumpWidget(_app(ai: ai));
    await _settle(tester);

    expect(ai.configStatus, ServerConfigStatus.ready);
    expect(find.text(I18n.tr('statistics.ai.disabled_hint')), findsOneWidget);
    expect(find.text(I18n.tr('statistics.ai.config.failed')), findsNothing);
    expect(find.text(I18n.tr('statistics.ai.config.loading')), findsNothing);
    expect(
      _aiButton(tester, I18n.tr('statistics.ai.generate')).onPressed,
      isNull,
    );
  });

  testWidgets('已启用：ready 且管理员开启时可生成', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ai = AiService()
      ..updateFromServerConfig(const {'ai_enabled': true, 'ai_model': 'm'});
    await tester.pumpWidget(_app(ai: ai));
    await _settle(tester);

    expect(ai.enabled, isTrue);
    expect(find.text(I18n.tr('statistics.ai.disabled_hint')), findsNothing);
    expect(
      _aiButton(tester, I18n.tr('statistics.ai.generate')).onPressed,
      isNotNull,
    );
  });
}
