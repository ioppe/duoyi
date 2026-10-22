import 'dart:convert';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Finder get _sheet => find.byType(AppModalSheet);

Finder _inSheet(Finder matching) =>
    find.descendant(of: _sheet, matching: matching);

Finder get _scroll => _inSheet(find.byType(Scrollable)).first;

/// Drives the real 用户组 tab so the create entry point itself is covered.
Future<List<String>> _openGroupCreate(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final requests = <String>[];
  final client = ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'admin-token',
    httpClient: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' && request.url.path == '/api/admin/groups') {
        return http.Response(
          json.encode({
            'items': [
              {
                'id': 'group_default',
                'name': '默认组',
                'description': '',
                'is_active': true,
                'user_count': 0,
              },
            ],
            'total': 1,
            'limit': 20,
            'offset': 0,
            'has_more': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    }),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: _FakeAuthProvider(
        state: const AuthState(
          userId: 'admin',
          username: 'admin',
          token: 'admin-token',
          isAdmin: true,
          adminPermissions: ['*'],
        ),
        client: client,
      ),
      child: const MaterialApp(home: AdminScreen(initialTabIndex: 5)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('新增用户组'));
  await tester.pumpAndSettle();
  return requests;
}

void main() {
  testWidgets('新增用户组入口使用共享底部弹窗，取消不写入', (tester) async {
    final requests = await _openGroupCreate(tester);

    expect(_sheet, findsOneWidget);
    expect(_inSheet(find.text('新增用户组')), findsOneWidget);
    expect(_inSheet(find.byType(TextField)), findsNWidgets(2));

    await tester.tap(_inSheet(find.text('取消')));
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
    expect(requests.where((r) => r.startsWith('POST')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏键盘弹起时能滚动到保存按钮', (tester) async {
    await _openGroupCreate(tester, size: const Size(360, 640));

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();

    final save = _inSheet(find.text('保存'));
    expect(save, findsOneWidget);
    await tester.scrollUntilVisible(save, 120, scrollable: _scroll);
    await tester.pumpAndSettle();

    expect(tester.getRect(save).bottom, lessThanOrEqualTo(640 - 280 + 1));
    expect(tester.takeException(), isNull);
  });
}

class _FakeAuthProvider extends AuthProvider {
  final AuthState _fakeState;
  final ApiClient _fakeClient;

  _FakeAuthProvider({required AuthState state, required ApiClient client})
    : _fakeState = state,
      _fakeClient = client;

  @override
  AuthState get state => _fakeState;

  @override
  ApiClient get client => _fakeClient;
}
