import 'dart:convert';
import 'dart:io';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/feedback_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('FeedbackScreen shows logged-out state without network', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        auth: _FakeAuthProvider(
          state: const AuthState(),
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            httpClient: MockClient((_) async {
              fail('未登录状态不应请求反馈接口');
            }),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('许愿与反馈'), findsWidgets);
    expect(find.text('登录后可查看反馈记录'), findsWidgets);
    expect(find.byKey(const ValueKey('feedback_submit_fab')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('feedback_submit_page_card')),
      findsNothing,
    );
  });

  testWidgets('FeedbackSubmitScreen initialCategory selects category menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        screen: const FeedbackSubmitScreen(initialCategory: 'bug'),
        auth: _FakeAuthProvider(
          state: const AuthState(
            userId: 'u1',
            username: 'tester',
            token: 'token',
          ),
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            httpClient: MockClient((_) async {
              fail('打开独立提交页不应先请求反馈接口');
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('提交许愿与反馈'), findsWidgets);
    expect(find.text('问题反馈'), findsOneWidget);
    expect(find.text('类型'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('feedback_record_pagination')),
      findsNothing,
    );
  });

  testWidgets('FeedbackScreen loads history and submits feedback', (
    tester,
  ) async {
    final requests = <String>[];
    final bodies = <Map<String, dynamic>>[];
    var getCount = 0;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'token',
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'GET' && request.url.path == '/api/feedback/me') {
          getCount++;
          expect(request.url.queryParameters['page'], isNotNull);
          expect(request.url.queryParameters['page_size'], '10');
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 1,
                  'category': 'bug',
                  'content': getCount == 1 ? '通知没有声音' : '小组件想要月历',
                  'status': getCount == 1 ? 'in_progress' : 'open',
                  'admin_reply': getCount == 1 ? '已加入排查' : '',
                },
              ],
              'total': 1,
              'page': 1,
              'page_size': 10,
              'total_pages': 1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/api/feedback') {
          bodies.add(json.decode(request.body) as Map<String, dynamic>);
          return http.Response(
            json.encode({'id': 2}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _wrap(
        screen: const FeedbackScreen(),
        auth: _FakeAuthProvider(
          state: const AuthState(
            userId: 'u1',
            username: 'tester',
            token: 'token',
          ),
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('许愿与反馈'), findsOneWidget);
    expect(find.text('反馈记录'), findsOneWidget);
    expect(find.text('通知没有声音'), findsOneWidget);
    expect(find.text('管理员回复'), findsOneWidget);
    expect(find.text('已加入排查'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('feedback_record_card_tap_target')),
    );
    await tester.pumpAndSettle();
    expect(find.text('反馈详情'), findsOneWidget);
    expect(find.text('问题反馈'), findsWidgets);
    expect(find.text('处理中'), findsWidgets);
    expect(find.text('内容'), findsOneWidget);
    expect(find.text('管理员回复'), findsWidgets);
    final detailText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data ?? '')
        .join('\n');
    expect(detailText, contains('通知没有声音'));
    expect(detailText, contains('已加入排查'));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('feedback_record_swipe_actions')).first,
      const Offset(-96, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('feedback_record_detail_action')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('feedback_record_detail_action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('反馈详情'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('feedback_submit_fab')));
    await tester.pumpAndSettle();
    expect(find.byType(FeedbackSubmitScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('feedback_submit_content')),
      '小组件想要月历',
    );
    await tester.tap(find.byKey(const ValueKey('feedback_submit_page_button')));
    await tester.pumpAndSettle();

    expect(requests, <String>[
      'GET /api/feedback/me',
      'POST /api/feedback',
      'GET /api/feedback/me',
    ]);
    expect(bodies.single['category'], 'feature');
    expect(bodies.single['content'], '小组件想要月历');
    expect(find.byType(FeedbackSubmitScreen), findsNothing);
    expect(find.text('小组件想要月历'), findsOneWidget);
  });

  testWidgets('Feedback record swipe state resets after pagination', (
    tester,
  ) async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'token',
      httpClient: MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/api/feedback/me') {
          final page = request.url.queryParameters['page'] ?? '1';
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': page == '1' ? 1 : 2,
                  'category': 'bug',
                  'content': page == '1' ? '第一页反馈' : '第二页反馈',
                  'status': 'open',
                  'admin_reply': '',
                },
              ],
              'total': 2,
              'page': int.parse(page),
              'page_size': 10,
              'total_pages': 2,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _wrap(
        screen: const FeedbackScreen(),
        auth: _FakeAuthProvider(
          state: const AuthState(
            userId: 'u1',
            username: 'tester',
            token: 'token',
          ),
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('feedback_record_swipe_actions')).first,
      const Offset(-96, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('feedback_record_detail_action')),
      findsOneWidget,
    );

    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();

    expect(find.text('第二页反馈'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('feedback_record_detail_action')),
      findsNothing,
    );
  });

  test(
    'FeedbackScreen separates records page from third-level submit page',
    () {
      final source = File(
        'lib/screens/feedback_screen.dart',
      ).readAsStringSync();

      expect(source, contains("title: const Text('许愿与反馈')"));
      expect(source, contains("title: '反馈记录'"));
      expect(
        source,
        contains('class FeedbackSubmitScreen extends StatefulWidget'),
      );
      expect(source, contains('appBar: AppBar('));
      expect(source, contains("title: const Text('提交许愿与反馈')"));
      expect(
        source,
        contains("key: const ValueKey('feedback_submit_page_card')"),
      );
      expect(
        source,
        contains("key: const ValueKey('feedback_three_level_menu')"),
      );
      expect(
        source,
        contains("key: const ValueKey('feedback_record_pagination')"),
      );
      expect(source, contains("key: const ValueKey('feedback_submit_fab')"));
      expect(
        source,
        contains("key: const ValueKey('feedback_record_swipe_actions')"),
      );
      expect(source, contains("ValueKey('feedback_record_swipe_\$recordId')"));
      expect(source, contains('required this.recordId'));
      expect(source, contains('void didUpdateWidget('));
      expect(source, contains('widget.recordId != oldWidget.recordId'));
      expect(source, contains("'feedback_record_detail_action'"));
      expect(source, contains("title: const Text('反馈详情')"));
      expect(source, contains('const int _pageSize = 10'));
      expect(source, contains('PopupMenuButton<String>'));
      expect(source, contains('onPointerDown: (_)'));
      expect(source, contains('FocusManager.instance.primaryFocus?.unfocus()'));
      expect(
        source,
        contains("for (final category in const ['feature', 'bug', 'wish'])"),
      );
      expect(source, contains('floatingActionButton: AppCreateFab('));
      expect(
        File('lib/widgets/app_create_fab.dart').readAsStringSync(),
        contains('return FloatingActionButton.extended('),
      );
      expect(source, contains('Navigator.push<bool>'));
      expect(
        source,
        contains('FeedbackSubmitScreen(initialCategory: category)'),
      );
      final recordPageStart = source.indexOf('class _FeedbackScreenState');
      final submitPageStart = source.indexOf('class FeedbackSubmitScreen');
      expect(recordPageStart, greaterThanOrEqualTo(0));
      expect(submitPageStart, greaterThan(recordPageStart));
      final recordPage = source.substring(recordPageStart, submitPageStart);
      expect(recordPage, isNot(contains('TextField(')));
      expect(recordPage, isNot(contains('/api/feedback\', {')));
      expect(source, isNot(contains('showAppModalSheet<void>')));
      expect(source, isNot(contains('Dismissible(')));
    },
  );

  test('FeedbackScreen ignores stale pagination responses', () {
    final source = File('lib/screens/feedback_screen.dart').readAsStringSync();

    expect(source, contains('int _loadSerial = 0'));
    expect(source, contains('final loadSerial = ++_loadSerial'));
    expect(source, contains('loadSerial != _loadSerial'));
    expect(source, contains('mounted && loadSerial == _loadSerial'));
    expect(source, isNot(contains('if (!auth.state.isLoggedIn || _loading)')));
  });
}

Widget _wrap({
  required AuthProvider auth,
  Widget screen = const FeedbackScreen(),
}) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(home: screen),
  );
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
