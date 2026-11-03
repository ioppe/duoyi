import 'dart:convert';
import 'dart:io';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  test(
    'Admin large-data tabs keep stable refresh state and ignore stale loads',
    () {
      final source = File('lib/screens/admin_screen.dart').readAsStringSync();

      expect(source, contains('class _AdminInlineLoadingIndicator'));
      expect(source, contains("label: '正在更新当前页'"));
      expect(source, contains("label: '正在更新反馈列表'"));
      expect(source, contains("text: '许愿与反馈'"));
      expect(source, contains("tooltip: '刷新当前页'"));
      final swipeActionsSource = source.substring(
        source.indexOf('class _AdminFeedbackSwipeActions'),
        source.indexOf('class _AdminFeedbackSwipeButton'),
      );
      expect(swipeActionsSource, contains('Stack('));
      expect(swipeActionsSource, contains('height: 42'));
      expect(swipeActionsSource, contains('if (_open)'));
      expect(swipeActionsSource, contains('Positioned.fill('));
      expect(
        swipeActionsSource,
        contains('static const double _actionRailWidth = 160'),
      );
      expect(swipeActionsSource, contains('TweenAnimationBuilder<double>('));
      expect(
        swipeActionsSource,
        contains('Tween<double>(end: _open ? -_actionRailWidth : 0)'),
      );
      expect(swipeActionsSource, contains('Transform.translate('));
      expect(swipeActionsSource, contains("tooltip: '查看反馈详情'"));
      expect(swipeActionsSource, contains("tooltip: '回复'"));
      expect(swipeActionsSource, contains("tooltip: '关闭'"));
      expect(swipeActionsSource, contains("tooltip: '删除'"));
      final feedbackDetailSource = source.substring(
        source.indexOf('Future<void> _showFeedbackDetail'),
        source.indexOf('Future<void> _deleteFeedback'),
      );
      expect(feedbackDetailSource, contains('maxWidth: 720'));
      expect(
        feedbackDetailSource,
        contains('FutureBuilder<Map<String, dynamic>>'),
      );
      expect(feedbackDetailSource, contains('initialData: summary'));
      expect(feedbackDetailSource, contains('详情加载失败，已展示列表摘要'));
      expect(
        feedbackDetailSource,
        contains('BoxConstraints(maxWidth: 640, maxHeight: 520)'),
      );
      final feedbackCardSource = source.substring(
        source.indexOf('final feedbackCard ='),
        source.indexOf('return _AdminFeedbackSwipeActions'),
      );
      expect(
        feedbackCardSource,
        contains('final feedbackCard = AppSurfaceCard('),
      );
      expect(feedbackCardSource, isNot(contains('_AdminListTileCard(')));
      expect(
        source,
        isNot(contains("trailing: Row(children: [TextButton")),
        reason: '反馈列表操作不能回退成固定 trailing 按钮占用文本区域。',
      );
      expect(source, contains('final loadSerial = ++_loadSerial;'));
      expect(
        RegExp(r'int _loadSerial = 0;').allMatches(source).length,
        greaterThanOrEqualTo(5),
      );
      expect(
        source,
        contains('if (!mounted || loadSerial != _loadSerial) return;'),
      );
      expect(
        source,
        contains('if (mounted && loadSerial == _loadSerial) setState'),
      );
    },
  );

  test('Admin users and groups hide unfinished image capabilities', () {
    final source = File('lib/screens/admin_screen.dart').readAsStringSync();

    expect(source, contains("ValueKey('admin_user_mobile_card_"));
    expect(source, contains("ValueKey('admin_user_identity_badges_"));
    expect(source, contains("ValueKey('admin_users_toolbar_actions')"));
    expect(source, contains('toolbarConstraints.maxWidth < 380'));
    expect(source, contains('constraints.maxWidth < 420'));
    expect(source, contains("label: const Text('更多详情')"));
    expect(source, contains('width: 40,'));
    expect(source, contains("title: '基础功能'"));
    expect(source, contains("title: '个人数据'"));
    expect(source, contains("title: '管理功能'"));
    expect(source, contains("title: '系统功能'"));
    expect(source, contains('class _AdminGroupSummaryCard'));
    expect(source, contains("subtitle: '管理成员分组和管理员权限模板'"));
    expect(source, contains('AppCompactDropdown<String>'));

    for (final hiddenTerm in [
      '生图',
      '改图',
      '图片额度',
      'image_generation',
      'image_edit',
      'draw',
      'generateImage',
      'default_generate',
      'default_edit',
      'image_mode',
    ]) {
      expect(source, isNot(contains(hiddenTerm)));
    }
  });

  testWidgets('Admin feedback tab lists feedback and paginates', (
    tester,
  ) async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          final offset =
              int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 7,
                  'username': 'tester',
                  'email': 'tester@example.com',
                  'email_verified': true,
                  'display_name': '测试同学',
                  'category': 'bug',
                  'content': offset == 0 ? '通知没有声音' : '第二页反馈',
                  'status': 'open',
                  'admin_reply': offset == 0 ? '请检查系统通知权限' : '',
                  'created_at': '2026-05-28 09:15:00',
                  'updated_at': '2026-05-28 10:20:00',
                },
                if (offset == 0)
                  {
                    'id': 8,
                    'username': 'tester',
                    'email': 'tester@example.com',
                    'email_verified': false,
                    'display_name': '',
                    'category': 'feature',
                    'content': '希望支持批量处理',
                    'status': 'in_progress',
                    'admin_reply': '处理中',
                    'created_at': '2026-05-27 08:00:00',
                    'updated_at': '2026-05-27 08:30:00',
                  },
              ],
              'total': 25,
              'limit':
                  int.tryParse(request.url.queryParameters['limit'] ?? '20') ??
                  20,
              'offset': offset,
              'has_more': offset == 0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback/7') {
          return http.Response(
            json.encode({
              'id': 7,
              'username': 'tester',
              'email': 'tester@example.com',
              'email_verified': true,
              'display_name': '测试同学',
              'category': 'bug',
              'content': '完整详情：通知没有声音且重复弹出两条',
              'status': 'open',
              'admin_reply': '完整回复：已检查详情接口返回',
              'created_at': '2026-05-28 09:15:00',
              'updated_at': '2026-05-28 10:20:00',
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 7)),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('测试同学', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('@tester', skipOffstage: false), findsWidgets);
    expect(
      find.textContaining('tester@example.com (已验证)', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('tester@example.com (未验证)', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('问题反馈', skipOffstage: false), findsWidgets);
    expect(find.textContaining('通知没有声音', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('第 1-2 条 / 共 25 条'), findsWidgets);
    expect(find.textContaining('本页 2 条 · 待处理 1'), findsOneWidget);
    expect(find.text('本页待处理转处理中'), findsOneWidget);
    expect(find.text('本页处理中转已解决'), findsOneWidget);
    expect(find.byType(Dismissible, skipOffstage: false), findsNothing);
    expect(find.byTooltip('反馈操作', skipOffstage: false), findsNothing);
    expect(find.byTooltip('查看反馈详情', skipOffstage: false), findsNothing);
    expect(find.byTooltip('回复', skipOffstage: false), findsNothing);
    expect(find.byTooltip('关闭', skipOffstage: false), findsNothing);
    expect(find.byTooltip('删除', skipOffstage: false), findsNothing);

    await tester.ensureVisible(find.textContaining('通知没有声音'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('通知没有声音'));
    await tester.pumpAndSettle();
    expect(find.text('反馈详情'), findsOneWidget);
    expect(find.text('内容'), findsWidgets);
    expect(find.textContaining('完整详情：通知没有声音且重复弹出两条'), findsOneWidget);
    expect(find.text('用户'), findsWidgets);
    expect(find.textContaining('测试同学'), findsWidgets);
    expect(find.text('账号'), findsWidgets);
    expect(find.textContaining('@tester'), findsWidgets);
    expect(
      find.textContaining('@tester · tester@example.com (已验证)'),
      findsWidgets,
    );
    expect(find.text('分类'), findsWidgets);
    expect(find.textContaining('问题反馈'), findsWidgets);
    expect(find.text('状态'), findsWidgets);
    expect(find.textContaining('待处理'), findsWidgets);
    expect(find.text('提交'), findsWidgets);
    expect(find.textContaining('2026-05-28 09:15:00'), findsWidgets);
    expect(find.text('更新'), findsWidgets);
    expect(find.textContaining('2026-05-28 10:20:00'), findsWidgets);
    expect(find.text('管理员回复'), findsWidgets);
    expect(find.textContaining('完整回复：已检查详情接口返回'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    final nextPageButton = find.descendant(
      of: find.byKey(const ValueKey('admin_feedback_pagination')),
      matching: find.byTooltip('下一页'),
    );
    await tester.ensureVisible(nextPageButton);
    await tester.tap(nextPageButton);
    await tester.pumpAndSettle();

    expect(
      requests,
      contains('GET /api/admin/feedback?sort=created_desc&limit=20&offset=0'),
    );
    expect(requests, contains('GET /api/admin/feedback/7'));
    expect(
      requests,
      contains('GET /api/admin/feedback?sort=created_desc&limit=20&offset=20'),
    );
  });

  testWidgets('Admin feedback pagination recovers from stale empty pages', (
    tester,
  ) async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          final offset =
              int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
          if (offset >= 20) {
            return http.Response(
              json.encode({
                'items': <Map<String, dynamic>>[],
                'total': 20,
                'limit': 20,
                'offset': offset,
                'has_more': false,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 7,
                  'username': 'tester',
                  'email': 'tester@example.com',
                  'email_verified': true,
                  'display_name': '测试同学',
                  'category': 'bug',
                  'content': '第一页反馈',
                  'status': 'open',
                  'admin_reply': '',
                },
              ],
              'total': 25,
              'limit': 20,
              'offset': 0,
              'has_more': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback/7') {
          return http.Response(
            json.encode({
              'id': 7,
              'username': 'reader',
              'email':
                  'reader-with-a-very-long-unbroken-email-address-for-admin-feedback-layout@example.invalid',
              'email_verified': true,
              'display_name': '长文本用户',
              'category': 'bug',
              'content': '完整详情：低高度窄屏下仍然需要先看到反馈正文，详情接口返回的长文本也不能让弹层溢出。',
              'status': 'open',
              'admin_reply':
                  '超长回复token_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_用于验证详情弹层横向滚动不撑破布局',
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 7)),
      ),
    );

    await tester.pumpAndSettle();
    final nextPageButton = find.descendant(
      of: find.byKey(const ValueKey('admin_feedback_pagination')),
      matching: find.byTooltip('下一页'),
    );
    await tester.ensureVisible(nextPageButton);
    await tester.tap(nextPageButton);
    await tester.pumpAndSettle();

    expect(
      requests,
      contains('GET /api/admin/feedback?sort=created_desc&limit=20&offset=20'),
    );
    expect(
      requests,
      contains('GET /api/admin/feedback?sort=created_desc&limit=20&offset=0'),
    );
    expect(
      requests
          .where(
            (request) =>
                request ==
                'GET /api/admin/feedback?sort=created_desc&limit=20&offset=0',
          )
          .length,
      greaterThanOrEqualTo(2),
    );
    expect(find.textContaining('第 21-20 条'), findsNothing);
    expect(find.textContaining('第 2/1 页'), findsNothing);
  });

  testWidgets('Admin feedback pagination stays compact on narrow screens', (
    tester,
  ) async {
    final previousSize = tester.view.physicalSize;
    final previousDevicePixelRatio = tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(() {
      tester.view.physicalSize = previousSize;
      tester.view.devicePixelRatio = previousDevicePixelRatio;
    });

    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 7,
                  'username': 'tester',
                  'email': 'tester@example.com',
                  'email_verified': true,
                  'display_name': '测试同学',
                  'category': 'bug',
                  'content': '窄屏反馈内容需要保持足够展示区域',
                  'status': 'open',
                  'admin_reply': '',
                },
              ],
              'total': 25,
              'limit': 20,
              'offset': 0,
              'has_more': true,
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 7)),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final pagination = find.byKey(const ValueKey('admin_feedback_pagination'));
    final row = find
        .ancestor(
          of: find.textContaining('窄屏反馈内容需要保持足够展示区域'),
          matching: find.byKey(const ValueKey('admin_feedback_swipe_7')),
        )
        .first;
    expect(pagination, findsOneWidget);
    expect(row, findsOneWidget);

    final paginationRect = tester.getRect(pagination);
    final rowRect = tester.getRect(row);
    expect(paginationRect.height, lessThanOrEqualTo(80));
    expect(rowRect.bottom, lessThan(paginationRect.top));
    expect(find.byTooltip('下一页'), findsWidgets);
  });

  testWidgets('Admin feedback stays readable on low-height narrow screens', (
    tester,
  ) async {
    final previousSize = tester.view.physicalSize;
    final previousDevicePixelRatio = tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 520);
    addTearDown(() {
      tester.view.physicalSize = previousSize;
      tester.view.devicePixelRatio = previousDevicePixelRatio;
    });

    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 7,
                  'username': 'reader',
                  'email': 'reader@example.com',
                  'email_verified': true,
                  'display_name': '长文本用户',
                  'category': 'bug',
                  'content': '低高度窄屏下仍然需要先看到反馈正文，而不是被分页、回复、删除按钮挤占。',
                  'status': 'open',
                  'admin_reply': '',
                },
                {
                  'id': 8,
                  'username': 'worker',
                  'email': 'worker@example.com',
                  'email_verified': false,
                  'display_name': '处理中用户',
                  'category': 'feature',
                  'content': '处理中反馈也要保持正文区域可读。',
                  'status': 'in_progress',
                  'admin_reply': '已收到，正在跟进。',
                },
                {
                  'id': 9,
                  'username': 'done',
                  'email': 'done@example.com',
                  'email_verified': true,
                  'display_name': '已解决用户',
                  'category': 'wish',
                  'content': '已解决反馈用于触发第三个批量按钮换行风险。',
                  'status': 'resolved',
                  'admin_reply': '已解决。',
                },
              ],
              'total': 43,
              'limit': 20,
              'offset': 0,
              'has_more': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback/7') {
          return http.Response(
            json.encode({
              'id': 7,
              'username': 'reader',
              'email':
                  'reader-with-a-very-long-unbroken-email-address-for-admin-feedback-layout@example.invalid',
              'email_verified': true,
              'display_name': '长文本用户',
              'category': 'bug',
              'content': '完整详情：低高度窄屏下仍然需要先看到反馈正文，详情接口返回的长文本也不能让弹层溢出。',
              'status': 'open',
              'admin_reply':
                  '超长回复token_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_用于验证详情弹层横向滚动不撑破布局',
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 7)),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('查看反馈详情', skipOffstage: false), findsNothing);
    expect(find.byTooltip('回复', skipOffstage: false), findsNothing);
    expect(find.byTooltip('关闭', skipOffstage: false), findsNothing);
    expect(find.byTooltip('删除', skipOffstage: false), findsNothing);

    final pagination = find.byKey(const ValueKey('admin_feedback_pagination'));
    final firstRow = find.byKey(const ValueKey('admin_feedback_swipe_7'));
    expect(pagination, findsOneWidget);
    expect(firstRow, findsOneWidget);

    final paginationRect = tester.getRect(pagination);
    final firstRowRect = tester.getRect(firstRow);
    final contentRect = tester.getRect(
      find.textContaining('低高度窄屏下仍然需要先看到反馈正文').first,
    );
    expect(paginationRect.height, lessThanOrEqualTo(80));
    expect(firstRowRect.top, greaterThanOrEqualTo(0));
    expect(firstRowRect.bottom, lessThan(paginationRect.top));
    expect(firstRowRect.height, greaterThanOrEqualTo(64));
    expect(
      contentRect.right,
      greaterThan(firstRowRect.right - 80),
      reason: '详情/回复/关闭/删除操作不能在未左滑时预留右侧按钮区域。',
    );

    await tester.tap(find.textContaining('低高度窄屏下仍然需要先看到反馈正文'));
    await tester.pumpAndSettle();
    expect(find.text('反馈详情'), findsOneWidget);
    expect(find.text('内容'), findsWidgets);
    expect(find.textContaining('完整详情：低高度窄屏下仍然需要先看到反馈正文'), findsOneWidget);
    expect(requests, contains('GET /api/admin/feedback/7'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin feedback tab bulk-updates current page open feedback', (
    tester,
  ) async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 7,
                  'username': 'tester',
                  'email': 'tester@example.com',
                  'email_verified': true,
                  'display_name': '测试同学',
                  'category': 'bug',
                  'content': '通知没有声音',
                  'status': 'open',
                  'admin_reply': '',
                },
                {
                  'id': 8,
                  'username': 'tester',
                  'email': 'tester@example.com',
                  'email_verified': true,
                  'display_name': '测试同学',
                  'category': 'feature',
                  'content': '希望支持批量处理',
                  'status': 'in_progress',
                  'admin_reply': '处理中',
                },
              ],
              'total': 2,
              'limit': 20,
              'offset': 0,
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/admin/feedback/bulk-status') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['feedback_ids'], [7]);
          expect(body['status'], 'in_progress');
          return http.Response(
            json.encode({'status': 'ok', 'updated': 1}),
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 7)),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('本页待处理转处理中'));
    await tester.pumpAndSettle();

    expect(requests, contains('POST /api/admin/feedback/bulk-status'));
  });

  testWidgets('Admin feedback tab bulk-closes current page resolved feedback', (
    tester,
  ) async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 9,
                  'username': 'done',
                  'email': 'done@example.com',
                  'email_verified': true,
                  'display_name': '已解决用户',
                  'category': 'wish',
                  'content': '已解决反馈可批量关闭',
                  'status': 'resolved',
                  'admin_reply': '已解决。',
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
        if (request.method == 'POST' &&
            request.url.path == '/api/admin/feedback/bulk-status') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['feedback_ids'], [9]);
          expect(body['reply'], '已归档关闭。');
          expect(body['status'], 'closed');
          return http.Response(
            json.encode({'status': 'ok', 'updated': 1}),
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 7)),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('本页已解决转关闭'));
    await tester.pumpAndSettle();

    expect(requests, contains('POST /api/admin/feedback/bulk-status'));
  });

  testWidgets('Admin feedback swipe actions can reply and delete feedback', (
    tester,
  ) async {
    final requests = <String>[];
    var deleted = false;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          return http.Response(
            json.encode({
              'items': deleted
                  ? []
                  : [
                      {
                        'id': 7,
                        'username': 'tester',
                        'email': 'tester@example.com',
                        'email_verified': true,
                        'display_name': '测试同学',
                        'category': 'bug',
                        'content': '通知没有声音',
                        'status': 'open',
                        'admin_reply': '已安排排查通知通道',
                      },
                    ],
              'total': deleted ? 0 : 1,
              'limit': 20,
              'offset': 0,
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback/7') {
          return http.Response(
            json.encode({
              'id': 7,
              'username': 'tester',
              'email': 'tester@example.com',
              'email_verified': true,
              'display_name': '测试同学',
              'category': 'bug',
              'content': '完整详情：通知没有声音且重复弹出两条',
              'status': 'open',
              'admin_reply': '完整回复：已安排排查通知通道',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/admin/feedback/reply') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['feedback_id'], 7);
          expect(body['reply'], '已处理，请重试');
          expect(body['status'], 'open');
          return http.Response(
            json.encode({'status': 'ok'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/admin/feedback/bulk-status') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['feedback_ids'], [7]);
          expect(body['reply'], '已安排排查通知通道');
          expect(body['status'], 'closed');
          return http.Response(
            json.encode({'status': 'ok', 'updated': 1}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE' &&
            request.url.path == '/api/admin/feedback/7') {
          deleted = true;
          return http.Response(
            json.encode({'status': 'ok'}),
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 7)),
      ),
    );
    await tester.pumpAndSettle();

    final feedbackRow = find
        .ancestor(
          of: find.textContaining('通知没有声音'),
          matching: find.byKey(const ValueKey('admin_feedback_swipe_7')),
        )
        .first;
    expect(feedbackRow, findsOneWidget);
    expect(find.byTooltip('查看反馈详情', skipOffstage: false), findsNothing);
    expect(find.byTooltip('回复', skipOffstage: false), findsNothing);
    expect(find.byTooltip('关闭', skipOffstage: false), findsNothing);
    expect(find.byTooltip('删除', skipOffstage: false), findsNothing);
    expect(tester.getRect(feedbackRow).width, greaterThan(260));
    await tester.ensureVisible(feedbackRow);
    await tester.pumpAndSettle();
    await tester.tap(feedbackRow);
    await tester.pumpAndSettle();
    expect(find.text('反馈详情'), findsOneWidget);
    expect(find.textContaining('完整详情：通知没有声音且重复弹出两条'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.drag(feedbackRow, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.byTooltip('查看反馈详情'), findsOneWidget);
    expect(find.byTooltip('回复'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);

    final rowRect = tester.getRect(feedbackRow);
    final detailRect = tester.getRect(find.byTooltip('查看反馈详情'));
    final replyRect = tester.getRect(find.byTooltip('回复'));
    final closeRect = tester.getRect(find.byTooltip('关闭'));
    final deleteRect = tester.getRect(find.byTooltip('删除'));
    final railLeft = [
      detailRect.left,
      replyRect.left,
      closeRect.left,
      deleteRect.left,
    ].reduce((a, b) => a < b ? a : b);
    final railRight = [
      detailRect.right,
      replyRect.right,
      closeRect.right,
      deleteRect.right,
    ].reduce((a, b) => a > b ? a : b);
    expect(railRight - railLeft, lessThanOrEqualTo(164));
    expect(railRight, lessThanOrEqualTo(rowRect.right));
    expect(railLeft, greaterThanOrEqualTo(rowRect.right - 164));

    await tester.tap(find.byTooltip('查看反馈详情'));
    await tester.pumpAndSettle();
    expect(find.text('反馈详情'), findsOneWidget);
    expect(find.text('用户'), findsWidgets);
    expect(find.textContaining('测试同学'), findsWidgets);
    expect(find.text('账号'), findsWidgets);
    expect(find.textContaining('@tester'), findsWidgets);
    expect(find.text('分类'), findsWidgets);
    expect(find.textContaining('问题反馈'), findsWidgets);
    expect(find.text('状态'), findsWidgets);
    expect(find.textContaining('待处理'), findsWidgets);
    expect(find.text('内容'), findsWidgets);
    expect(find.textContaining('完整详情：通知没有声音且重复弹出两条'), findsOneWidget);
    expect(find.text('管理员回复'), findsWidgets);
    expect(find.textContaining('完整回复：已安排排查通知通道'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.drag(feedbackRow, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('关闭反馈？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '关闭'));
    await tester.pumpAndSettle();

    await tester.drag(feedbackRow, const Offset(-180, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('回复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '已处理，请重试');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    await tester.drag(feedbackRow, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(requests, contains('POST /api/admin/feedback/reply'));
    expect(requests, contains('POST /api/admin/feedback/bulk-status'));
    expect(
      requests
          .where((request) => request == 'GET /api/admin/feedback/7')
          .length,
      greaterThanOrEqualTo(2),
    );
    expect(requests, contains('DELETE /api/admin/feedback/7'));
    expect(find.text('通知没有声音'), findsNothing);
  });

  testWidgets(
    'Admin groups tab hides legacy currency and saves other fields without overwriting defaults',
    (tester) async {
      final requests = <String>[];
      Map<String, dynamic>? savedPayload;
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'admin-token',
        httpClient: MockClient((request) async {
          final query = request.url.query.isEmpty
              ? ''
              : '?${request.url.query}';
          requests.add('${request.method} ${request.url.path}$query');
          if (request.method == 'GET' &&
              request.url.path == '/api/admin/groups') {
            return http.Response(
              json.encode({
                'items': [
                  {
                    'id': 'group_default',
                    'name': '默认用户',
                    'description': '新注册用户默认分组。注册赠送 100 时光币。',
                    'default_time_coins':
                        savedPayload?['default_time_coins'] ?? 100,
                    'is_active': savedPayload?['is_active'] ?? true,
                    'user_count': 3,
                    'created_at': '2026-05-29 00:00:00',
                    'updated_at': '2026-05-29 00:00:00',
                  },
                ],
                'total': 1,
                'limit':
                    int.tryParse(
                      request.url.queryParameters['limit'] ?? '20',
                    ) ??
                    20,
                'offset':
                    int.tryParse(
                      request.url.queryParameters['offset'] ?? '0',
                    ) ??
                    0,
                'has_more': false,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if ((request.method == 'PATCH' || request.method == 'PUT') &&
              request.url.path == '/api/admin/groups/group_default') {
            savedPayload = json.decode(request.body) as Map<String, dynamic>;
            return http.Response(
              json.encode({
                'id': 'group_default',
                'name': savedPayload!['name'],
                'description': savedPayload!['description'],
                'default_time_coins': savedPayload!['default_time_coins'],
                'is_active': savedPayload!['is_active'],
                'user_count': 3,
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
            ),
            client: client,
          ),
          child: const MaterialApp(home: AdminScreen(initialTabIndex: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('用户组管理'), findsOneWidget);
      expect(find.textContaining('时光币'), findsNothing);
      expect(find.text('新注册用户默认分组'), findsOneWidget);
      expect(find.textContaining('生图'), findsNothing);
      expect(find.textContaining('改图'), findsNothing);
      expect(find.textContaining('图片额度'), findsNothing);

      final pagination = find.byKey(
        const ValueKey('admin_groups_pagination_bar'),
      );
      final groupText = find.text('新注册用户默认分组').first;
      expect(pagination, findsOneWidget);
      expect(
        tester.getRect(groupText).bottom,
        lessThan(tester.getRect(pagination).top),
      );

      await tester.tap(find.byTooltip('编辑用户组').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('默认生图额度'), findsNothing);
      expect(find.textContaining('默认改图额度'), findsNothing);
      expect(find.textContaining('默认生图历史保留'), findsNothing);
      expect(find.textContaining('默认改图历史保留'), findsNothing);
      expect(find.textContaining('图片额度模式'), findsNothing);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(find.textContaining('时光币'), findsNothing);
      await tester.enterText(fields.at(0), '默认成员');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(requests, contains('GET /api/admin/groups?limit=20&offset=0'));
      expect(requests, contains('PATCH /api/admin/groups/group_default'));
      expect(savedPayload?.containsKey('default_time_coins'), isFalse);
      expect(savedPayload?['name'], '默认成员');
      expect(savedPayload?['description'], '新注册用户默认分组。注册赠送 100 时光币。');
      expect(savedPayload?.containsKey('default_generate_quota'), isFalse);
      expect(savedPayload?.containsKey('default_edit_quota'), isFalse);
      expect(find.textContaining('时光币'), findsNothing);
    },
  );

  test('AdminApi user export includes online filter', () async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        expect(request.url.queryParameters['online'], 'true');
        expect(request.url.queryParameters['status'], isNull);
        return http.Response(
          'user_id,username\nuser-a,user-a\n',
          200,
          headers: {'content-type': 'text/csv'},
        );
      }),
    );

    final csv = await AdminApi(
      client,
    ).exportUsersCsv(online: true, sort: 'created_desc');

    expect(csv, contains('user-a'));
    expect(
      requests,
      contains(
        'GET /api/admin/users/export.csv?online=true&sort=created_desc&limit=5000',
      ),
    );
  });

  testWidgets('Admin groups header keeps add action inside 320px viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/groups') {
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 'group_default',
                  'name': '默认用户组',
                  'description': '默认普通用户使用的用户组',
                  'default_time_coins': 100,
                  'is_active': true,
                  'user_count': 3,
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 5)),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('用户组管理'), findsOneWidget);
    expect(find.text('新增用户组'), findsOneWidget);
    final addButtonRect = tester.getRect(find.text('新增用户组'));
    expect(addButtonRect.left, greaterThanOrEqualTo(0));
    expect(addButtonRect.right, lessThanOrEqualTo(320));
  });

  testWidgets(
    'Admin users search toolbar and long identity badges fit 320px viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const longGroupId = 'group_long';
      const longRoleId = 'role_long';
      const longGroupName = '超长用户组名称用于验证窄屏不会撑出卡片边界';
      const longRoleName = '超长角色名称用于验证窄屏不会撑出卡片边界';
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'admin-token',
        httpClient: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/admin/users') {
            return http.Response(
              json.encode({
                'items': [
                  {
                    'user_id': 'user-a',
                    'username': 'layout-user-with-long-name',
                    'email':
                        'very-long-layout-user-email-address@example.invalid',
                    'email_verified': false,
                    'display_name': '窄屏布局测试用户',
                    'is_admin': true,
                    'admin_permissions': ['users'],
                    'is_disabled': false,
                    'created_at': '2026-05-20 00:00:00',
                    'last_login_at': '2026-05-20 00:00:00',
                    'last_active_at': '2026-05-20 00:00:00',
                    'feedback_count': 0,
                    'online': true,
                    'group_id': longGroupId,
                    'role_id': longRoleId,
                    'coin_balance': 123,
                    'lifetime_coins': 456,
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
          if (request.method == 'GET' &&
              request.url.path == '/api/admin/groups') {
            return http.Response(
              json.encode({
                'items': [
                  {
                    'id': longGroupId,
                    'name': longGroupName,
                    'description': '',
                    'default_time_coins': 100,
                    'is_active': true,
                    'user_count': 1,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/admin/roles') {
            return http.Response(
              json.encode([
                {
                  'id': longRoleId,
                  'name': longRoleName,
                  'description': '',
                  'permission_codes': ['users'],
                  'is_active': true,
                  'user_count': 1,
                },
              ]),
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
            ),
            client: client,
          ),
          child: const MaterialApp(home: AdminScreen(initialTabIndex: 4)),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('admin_users_toolbar_actions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin_user_identity_badges_user-a')),
        findsOneWidget,
      );
      expect(find.text(longRoleName), findsOneWidget);
      expect(find.text(longGroupName), findsOneWidget);

      final toolbarRect = tester.getRect(
        find.byKey(const ValueKey('admin_users_toolbar_actions')),
      );
      final badgesRect = tester.getRect(
        find.byKey(const ValueKey('admin_user_identity_badges_user-a')),
      );
      expect(toolbarRect.left, greaterThanOrEqualTo(0));
      expect(toolbarRect.right, lessThanOrEqualTo(320));
      expect(badgesRect.left, greaterThanOrEqualTo(0));
      expect(badgesRect.right, lessThanOrEqualTo(320));
    },
  );

  testWidgets('Admin users tab bulk-disables selected users', (tester) async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' && request.url.path == '/api/admin/users') {
          return http.Response(
            json.encode({
              'items': [
                {
                  'user_id': 'admin',
                  'username': 'admin',
                  'email': 'admin@example.com',
                  'email_verified': true,
                  'display_name': '',
                  'is_admin': true,
                  'is_disabled': false,
                  'created_at': '2026-05-20 00:00:00',
                  'last_login_at': '2026-05-20 00:00:00',
                  'last_active_at': '2026-05-20 00:00:00',
                  'feedback_count': 0,
                  'online': true,
                },
                {
                  'user_id': 'user-a',
                  'username': 'user-a',
                  'email': 'a@example.com',
                  'email_verified': false,
                  'display_name': 'A',
                  'is_admin': false,
                  'is_disabled': false,
                  'created_at': '2026-05-20 00:00:00',
                  'last_login_at': null,
                  'last_active_at': null,
                  'feedback_count': 2,
                  'online': true,
                },
              ],
              'total': 2,
              'limit': 20,
              'offset': 0,
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/admin/users/bulk-status') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['user_ids'], ['user-a']);
          expect(body['is_disabled'], true);
          return http.Response(
            json.encode({'status': 'ok', 'updated': 1}),
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
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 4)),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '在线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选本页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量禁用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('禁用').last);
    await tester.pumpAndSettle();

    expect(
      requests,
      contains(
        'GET /api/admin/users?online=true&sort=created_desc&limit=20&offset=0',
      ),
    );
    expect(requests, contains('POST /api/admin/users/bulk-status'));
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
