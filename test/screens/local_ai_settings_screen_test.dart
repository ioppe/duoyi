import 'dart:io';

import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/local_ai_settings_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/local_ai_config_store.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('本机模式加载已保存配置，密钥输入框不回显', (tester) async {
    final store = _FakeLocalAiConfigStore(
      LocalAiConfig(
        enabled: true,
        baseUrl: 'https://local.example/v1',
        model: 'local-model',
        apiKey: 'sk-saved',
      ),
    );
    final ai = AiService(
      localConfigStore: store,
      localHttpClient: MockClient((_) async {
        fail('加载本机配置不应发起网络请求');
      }),
    )..setRemoteAccountActive(false);

    await tester.pumpWidget(_wrap(ai));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('local_ai_loading')), findsNothing);
    expect(
      find.byKey(const ValueKey('local_ai_base_url_field')),
      findsOneWidget,
    );
    expect(
      _fieldText(tester, 'local_ai_base_url_field'),
      'https://local.example/v1',
    );
    expect(_fieldText(tester, 'local_ai_model_field'), 'local-model');
    expect(_fieldText(tester, 'local_ai_api_key_field'), isEmpty);
    expect(
      _fieldHint(tester, 'local_ai_api_key_field'),
      I18n.tr('ai.local.key_saved'),
    );
    expect(store.reads, 1);
  });

  testWidgets('保存本机配置写入存储，密钥输入框清空且地址草稿保留', (tester) async {
    final store = _FakeLocalAiConfigStore();
    final ai = AiService(
      localConfigStore: store,
      localHttpClient: MockClient((_) async {
        fail('保存不应直连测试本机服务');
      }),
    )..setRemoteAccountActive(false);

    await tester.pumpWidget(_wrap(ai));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('local_ai_base_url_field')),
      'https://draft.example/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('local_ai_model_field')),
      'draft-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('local_ai_api_key_field')),
      'sk-new',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('local_ai_save_button')),
    );
    await tester.tap(find.byKey(const ValueKey('local_ai_save_button')));
    await tester.pumpAndSettle();

    expect(store.writes, 1);
    expect(store.value.baseUrl, 'https://draft.example/v1');
    expect(store.value.model, 'draft-model');
    expect(store.value.apiKey, 'sk-new');
    expect(_fieldText(tester, 'local_ai_api_key_field'), isEmpty);
    expect(
      _fieldText(tester, 'local_ai_base_url_field'),
      'https://draft.example/v1',
    );
    expect(find.byKey(const ValueKey('local_ai_notice')), findsOneWidget);
  });

  testWidgets('保存后重开页面加载已保存配置，密钥仍不回显', (tester) async {
    final store = _FakeLocalAiConfigStore();
    final first = AiService(
      localConfigStore: store,
      localHttpClient: MockClient((_) async {
        fail('保存不应直连测试本机服务');
      }),
    )..setRemoteAccountActive(false);

    await tester.pumpWidget(_wrap(first));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('local_ai_base_url_field')),
      'https://draft.example/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('local_ai_model_field')),
      'draft-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('local_ai_api_key_field')),
      'sk-new',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('local_ai_save_button')),
    );
    await tester.tap(find.byKey(const ValueKey('local_ai_save_button')));
    await tester.pumpAndSettle();
    expect(store.writes, 1);

    // 卸载页面后用同一存储重开，模拟下次进入设置页。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final reopened = AiService(
      localConfigStore: store,
      localHttpClient: MockClient((_) async {
        fail('重开页面不应直连测试本机服务');
      }),
    )..setRemoteAccountActive(false);
    await tester.pumpWidget(_wrap(reopened));
    await tester.pumpAndSettle();

    expect(
      _fieldText(tester, 'local_ai_base_url_field'),
      'https://draft.example/v1',
    );
    expect(_fieldText(tester, 'local_ai_model_field'), 'draft-model');
    expect(_fieldText(tester, 'local_ai_api_key_field'), isEmpty);
    expect(
      _fieldHint(tester, 'local_ai_api_key_field'),
      I18n.tr('ai.local.key_saved'),
    );
  });

  testWidgets('测试连接只测当前草稿，不写入存储也不改启用状态', (tester) async {
    final store = _FakeLocalAiConfigStore(
      LocalAiConfig(
        enabled: true,
        baseUrl: 'https://saved.example/v1',
        model: 'saved-model',
      ),
    );
    var requests = 0;
    final ai = AiService(
      localConfigStore: store,
      localHttpClient: MockClient((request) async {
        requests++;
        return http.Response(
          '{"choices":[{"message":{"content":"pong"}}]}',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    )..setRemoteAccountActive(false);

    await tester.pumpWidget(_wrap(ai));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('local_ai_base_url_field')),
      'https://draft.example/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('local_ai_model_field')),
      'draft-model',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('local_ai_test_button')),
    );
    await tester.tap(find.byKey(const ValueKey('local_ai_test_button')));
    await tester.pumpAndSettle();

    expect(requests, greaterThan(0));
    expect(store.writes, 0);
    expect(store.value.enabled, isTrue);
    expect(store.value.baseUrl, 'https://saved.example/v1');
    expect(
      _fieldText(tester, 'local_ai_base_url_field'),
      'https://draft.example/v1',
    );
    expect(find.byKey(const ValueKey('local_ai_notice')), findsOneWidget);
  });

  testWidgets('远程登录只显示服务器 AI 状态，不读本机配置也不可编辑', (tester) async {
    final store = _FakeLocalAiConfigStore(
      LocalAiConfig(
        enabled: true,
        baseUrl: 'https://local.example/v1',
        model: 'local-model',
        apiKey: 'sk-saved',
      ),
    );
    final ai = AiService(
      localConfigStore: store,
      localHttpClient: MockClient((_) async {
        fail('远程模式不应发起本机请求');
      }),
    );
    ai.setRemoteAccountActive(true);

    await tester.pumpWidget(_wrap(ai));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local_ai_remote_status')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('local_ai_base_url_field')), findsNothing);
    expect(find.byKey(const ValueKey('local_ai_test_button')), findsNothing);
    expect(find.text(I18n.tr('ai.local.server_disabled')), findsOneWidget);
    expect(store.reads, 0);
    expect(store.writes, 0);
  });

  testWidgets('切到远程账号立即隐藏表单，切回本机重新加载本机配置', (tester) async {
    final store = _FakeLocalAiConfigStore(
      LocalAiConfig(
        enabled: true,
        baseUrl: 'https://local.example/v1',
        model: 'local-model',
      ),
    );
    final ai = AiService(
      localConfigStore: store,
      localHttpClient: MockClient((_) async {
        fail('本机模式不应发起网络请求');
      }),
    )..setRemoteAccountActive(false);

    await tester.pumpWidget(_wrap(ai));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('local_ai_base_url_field')),
      findsOneWidget,
    );

    ai.setRemoteAccountActive(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local_ai_base_url_field')), findsNothing);
    expect(
      find.byKey(const ValueKey('local_ai_remote_status')),
      findsOneWidget,
    );

    ai.setRemoteAccountActive(false);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('local_ai_base_url_field')),
      findsOneWidget,
    );
    expect(
      _fieldText(tester, 'local_ai_base_url_field'),
      'https://local.example/v1',
    );
  });

  testWidgets('清除本机配置需要确认，确认后清空存储与表单', (tester) async {
    final store = _FakeLocalAiConfigStore(
      LocalAiConfig(
        enabled: true,
        baseUrl: 'https://local.example/v1',
        model: 'local-model',
        apiKey: 'sk-saved',
      ),
    );
    final ai = AiService(
      localConfigStore: store,
      localHttpClient: MockClient((_) async {
        fail('清除配置不应发起网络请求');
      }),
    )..setRemoteAccountActive(false);

    await tester.pumpWidget(_wrap(ai));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('local_ai_clear_button')),
    );
    await tester.tap(find.byKey(const ValueKey('local_ai_clear_button')));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('ai.local.clear_title')), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, I18n.tr('action.cancel')));
    await tester.pumpAndSettle();
    expect(store.clears, 0);
    expect(
      _fieldText(tester, 'local_ai_base_url_field'),
      'https://local.example/v1',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('local_ai_clear_button')),
    );
    await tester.tap(find.byKey(const ValueKey('local_ai_clear_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, I18n.tr('action.confirm')),
    );
    await tester.pumpAndSettle();

    expect(store.clears, 1);
    expect(_fieldText(tester, 'local_ai_base_url_field'), isEmpty);
    expect(find.byKey(const ValueKey('local_ai_notice')), findsOneWidget);
  });

  testWidgets('320 宽 + 2 倍字号可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ai = AiService(
      localConfigStore: _FakeLocalAiConfigStore(
        LocalAiConfig(
          enabled: true,
          baseUrl: 'https://local.example/v1',
          model: 'local-model',
          apiKey: 'sk-saved',
        ),
      ),
      localHttpClient: MockClient((_) async {
        fail('不应发起网络请求');
      }),
    )..setRemoteAccountActive(false);

    await tester.pumpWidget(_wrap(ai, textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -240),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('1440 宽 + 2 倍字号表单限宽且不溢出', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ai = AiService(
      localConfigStore: _FakeLocalAiConfigStore(
        LocalAiConfig(
          enabled: true,
          baseUrl: 'https://local.example/v1',
          model: 'local-model',
        ),
      ),
      localHttpClient: MockClient((_) async {
        fail('不应发起网络请求');
      }),
    )..setRemoteAccountActive(false);

    await tester.pumpWidget(_wrap(ai, textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final fieldWidth = tester
        .getSize(find.byKey(const ValueKey('local_ai_base_url_field')))
        .width;
    expect(fieldWidth, lessThanOrEqualTo(DesignTokens.creationFormMaxWidth));
  });

  test('我的页设置分组始终提供本机 AI 入口，Web 端隐藏', () {
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();

    expect(mine, contains("import '../core/web_target.dart';"));
    expect(mine, contains("import 'local_ai_settings_screen.dart';"));
    expect(mine, contains("key: const ValueKey('mine_ai_settings_entry')"));
    expect(mine, contains('if (!WebTarget.isWebBuild)'));
    expect(mine, contains("label: I18n.tr('ai.local.title')"));
    expect(mine, contains("subtitle: I18n.tr('ai.local.entry_hint')"));
    expect(
      mine,
      contains('const BrandRouteSurface(child: LocalAiSettingsScreen())'),
    );
    final personal = mine.indexOf("mine.group.personal");
    final entry = mine.indexOf('mine_ai_settings_entry');
    final data = mine.indexOf("mine.group.data");
    expect(personal, greaterThanOrEqualTo(0));
    expect(entry, greaterThan(personal));
    expect(entry, lessThan(data));
  });
}

Widget _wrap(AiService ai, {double textScale = 1}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AiService>.value(value: ai),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      home: const BrandRouteSurface(child: LocalAiSettingsScreen()),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

String _fieldText(WidgetTester tester, String key) {
  final field = tester.widget<TextField>(find.byKey(ValueKey(key)));
  return field.controller?.text ?? '';
}

String? _fieldHint(WidgetTester tester, String key) {
  final field = tester.widget<TextField>(find.byKey(ValueKey(key)));
  return field.decoration?.hintText;
}

class _FakeLocalAiConfigStore implements LocalAiConfigStore {
  _FakeLocalAiConfigStore([LocalAiConfig? initial])
    : value = initial ?? LocalAiConfig(enabled: false, baseUrl: '', model: '');

  LocalAiConfig value;
  int reads = 0;
  int writes = 0;
  int clears = 0;

  @override
  Future<LocalAiConfig> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(LocalAiConfig config) async {
    writes++;
    value = config;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = LocalAiConfig(enabled: false, baseUrl: '', model: '');
  }
}
