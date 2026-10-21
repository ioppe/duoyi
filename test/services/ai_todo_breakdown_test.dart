import 'dart:convert';

import 'package:duoyi/core/ai_todo_breakdown.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

const _subtasks = ['收集项目资料', '整理项目提纲', '检查并提交文档'];

String _response([Map<String, Object?> overrides = const {}]) => jsonEncode({
  'subtasks': _subtasks,
  'list_group': '工作',
  'quadrant': 'Q2',
  'date_time': null,
  'has_time': false,
  ...overrides,
});

AiTodoBreakdown? _parse(
  Map<String, Object?> overrides, {
  List<String> listGroups = const ['工作', '生活'],
}) => AiTodoBreakdown.tryParse(_response(overrides), listGroups: listGroups);

AiService _serviceReturning(
  String content, {
  void Function(http.Request)? onRequest,
}) {
  final client = MockClient((request) async {
    onRequest?.call(request);
    return http.Response.bytes(
      utf8.encode(jsonEncode({'content': content})),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final service = AiService()
    ..attachClient(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'test-token',
        httpClient: client,
      ),
    )
    ..updateFromServerConfig({'ai_enabled': true});
  addTearDown(service.dispose);
  addTearDown(client.close);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
  });

  tearDown(() {
    AppClock.debugNow = null;
  });

  test(
    'optional concise title is normalized without breaking legacy replies',
    () {
      expect(_parse({'title': '  准备云计算\n评审问题  '})!.title, '准备云计算 评审问题');
      for (final value in <Object?>[
        null,
        '',
        '   ',
        123,
        {'name': '无效'},
        List.filled(81, '长').join(),
      ]) {
        expect(_parse({'title': value})!.title, isNull);
      }
      expect(
        AiTodoBreakdown.tryParse(_response(), listGroups: ['工作'])!.title,
        isNull,
      );
    },
  );

  test('const constructor supports caller-created suggestions', () {
    const minimal = AiTodoBreakdown(subtasks: ['收集资料']);
    expect(minimal.subtasks, ['收集资料']);
    expect(minimal.listGroupName, isNull);
    expect(minimal.quadrant, isNull);
    expect(minimal.dateTime, isNull);
    expect(minimal.hasTimeOfDay, isFalse);

    final date = AppClock.date(2026, 10, 23, 15);
    final complete = AiTodoBreakdown(
      subtasks: const ['收集资料'],
      listGroupName: '工作',
      quadrant: EisenhowerQuadrant.notUrgentImportant,
      dateTime: date,
      hasTimeOfDay: true,
    );
    expect(complete.listGroupName, '工作');
    expect(complete.quadrant, EisenhowerQuadrant.notUrgentImportant);
    expect(complete.dateTime, date);
    expect(complete.hasTimeOfDay, isTrue);
  });

  test(
    'one request includes app clock, zone, allowed groups and schema',
    () async {
      AppClock.debugNow = () => DateTime.utc(2026, 10, 22, 23, 30);
      final requests = <http.Request>[];
      final service = _serviceReturning(_response(), onRequest: requests.add);

      final result = await service.breakDownTodo(
        '  整理项目资料  ',
        listGroups: ['工作', '生活'],
      );

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/ai/chat');
      expect(request.headers['Authorization'], 'Bearer test-token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final system = body['system'] as String;
      final user = body['user'] as String;
      expect(user, contains('2026-10-23T07:30:00'));
      expect(user, contains('Asia/Shanghai'));
      expect(user, contains(jsonEncode(['工作', '生活'])));
      expect(user, contains('用户原文：整理项目资料'));
      for (final field in [
        'subtasks',
        'list_group',
        'quadrant',
        'date_time',
        'has_time',
      ]) {
        expect(system, contains('"$field"'));
      }
      for (final quadrant in ['Q1', 'Q2', 'Q3', 'Q4']) {
        expect(system, contains(quadrant));
      }
      expect(system, contains('3 到 7 条'));
      expect(system, contains('不创建新清单'));
      expect(system, contains('不要返回独立的低、中、高 priority'));
      expect(system, contains('原文有依据'));
      expect(system, contains('不要自行添加默认 9 点'));
      expect(result.subtasks, _subtasks);
      expect(result.listGroupName, '工作');
      expect(result.quadrant, EisenhowerQuadrant.notUrgentImportant);
      expect(result.dateTime, isNull);
      expect(result.hasTimeOfDay, isFalse);
    },
  );

  test(
    'provided now is converted to the selected New York wall time',
    () async {
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      AppClock.debugNow = () => DateTime.utc(2000);
      final requests = <http.Request>[];
      final service = _serviceReturning(_response(), onRequest: requests.add);

      final result = await service.breakDownTodo(
        '整理资料',
        listGroups: [],
        now: DateTime.utc(2026, 10, 23, 2, 30),
      );

      expect(requests, hasLength(1));
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['user'], contains('2026-10-22T22:30:00'));
      expect(body['user'], contains('America/New_York'));
      expect(body['user'], contains('listGroups）：[]'));
      expect(result.listGroupName, isNull);
    },
  );

  test(
    'service accepts fenced JSON and returns structured suggestions',
    () async {
      final service = _serviceReturning(
        '  ```json\r\n${_response({'date_time': '2026-10-23T15:00:00', 'has_time': true})}\r\n```\n',
      );
      final result = await service.breakDownTodo(
        '10月23日15点整理项目资料',
        listGroups: ['工作'],
      );

      expect(result.subtasks, _subtasks);
      expect(result.listGroupName, '工作');
      expect(result.quadrant, EisenhowerQuadrant.notUrgentImportant);
      expect(result.dateTime, AppClock.date(2026, 10, 23, 15));
      expect(result.hasTimeOfDay, isTrue);
    },
  );

  test('blank input fails before requesting AI', () async {
    final requests = <http.Request>[];
    final service = _serviceReturning(_response(), onRequest: requests.add);
    await expectLater(
      service.breakDownTodo(' \n ', listGroups: ['工作']),
      throwsA(isA<AiException>()),
    );
    expect(requests, isEmpty);
  });

  test('disabled AI still throws the existing service error', () async {
    final requests = <http.Request>[];
    final service = _serviceReturning(_response(), onRequest: requests.add)
      ..updateFromServerConfig({'ai_enabled': false});
    await expectLater(
      service.breakDownTodo('整理项目资料', listGroups: ['工作']),
      throwsA(isA<AiException>()),
    );
    expect(requests, isEmpty);
  });

  for (final (label, response) in <(String, String)>[
    ('empty response', ''),
    ('whitespace response', ' \n '),
    ('broken JSON', '{"subtasks":['),
    ('plain task lines', '收集资料\n整理提纲'),
    ('JSON array', '["收集资料"]'),
    ('JSON string', '"收集资料"'),
    ('JSON null', 'null'),
    ('missing subtasks', '{"quadrant":"Q2"}'),
    ('empty subtasks', _response({'subtasks': []})),
    ('string subtasks', _response({'subtasks': '收集资料'})),
    (
      'object subtasks',
      _response({
        'subtasks': {'title': '收集资料'},
      }),
    ),
    (
      'no usable strings',
      _response({
        'subtasks': [null, false, 42, {}, [], ' ', '- ', '1. '],
      }),
    ),
  ]) {
    test(
      '$label throws AiException without retry or raw JSON fallback',
      () async {
        var calls = 0;
        final service = _serviceReturning(response, onRequest: (_) => calls++);
        await expectLater(
          service.breakDownTodo('保留这段原文', listGroups: ['工作']),
          throwsA(isA<AiException>()),
        );
        expect(calls, 1);
      },
    );
  }

  test('cleans string subtasks, deduplicates and limits them to seven', () {
    final result = _parse({
      'subtasks': [
        ' 1. 收集资料 ',
        '收集资料',
        {'title': '不能把对象变成子任务'},
        42,
        null,
        '',
        ' - 整理\n 提纲 ',
        '整理 提纲',
        '* 联系同事',
        '4、检查附件',
        '• 校对文档',
        '2026 年预算复核',
        '提交文档',
        '超出的第八项',
      ],
    });
    expect(result!.subtasks, [
      '收集资料',
      '整理 提纲',
      '联系同事',
      '检查附件',
      '校对文档',
      '2026 年预算复核',
      '提交文档',
    ]);
    expect(() => result.subtasks.add('追加'), throwsUnsupportedError);
  });

  test('keeps usable subtasks when optional suggestions are invalid', () {
    final result = _parse({
      'list_group': '新的工作清单',
      'quadrant': 'high',
      'date_time': 'not a date',
      'has_time': true,
      'priority': 'high',
    });
    expect(result!.subtasks, _subtasks);
    expect(result.listGroupName, isNull);
    expect(result.quadrant, isNull);
    expect(result.dateTime, isNull);
    expect(result.hasTimeOfDay, isFalse);
  });

  test('group names must exactly match a supplied complete value', () {
    for (final value in ['工', '工作 ', '工作/生活', '未知', 1, null]) {
      expect(_parse({'list_group': value})!.listGroupName, isNull);
    }
    expect(_parse({'list_group': '工作'})!.listGroupName, '工作');
    expect(_parse({'list_group': '工作'}, listGroups: [])!.listGroupName, isNull);
  });

  test('maps only Q1 through Q4 to the existing quadrants', () {
    const expected = {
      'Q1': EisenhowerQuadrant.urgentImportant,
      'Q2': EisenhowerQuadrant.notUrgentImportant,
      'Q3': EisenhowerQuadrant.urgentNotImportant,
      'Q4': EisenhowerQuadrant.notUrgentNotImportant,
    };
    for (final entry in expected.entries) {
      expect(_parse({'quadrant': entry.key})!.quadrant, entry.value);
    }
    for (final value in ['q1', 'Q5', 'Q2 ', '重要不紧急', 'high', 2, null]) {
      expect(_parse({'quadrant': value})!.quadrant, isNull);
    }
  });

  for (final zone in ['Asia/Shanghai', 'America/New_York']) {
    test('local datetime uses $zone and preserves wall components', () async {
      await LocalTimezoneResolver.setApplicationTimeZone(zone);
      final result = _parse({
        'date_time': '2026-10-23T15:20:30.123456',
        'has_time': true,
      });
      final date = result!.dateTime!;
      expect(date, AppClock.date(2026, 10, 23, 15, 20, 30, 123, 456));
      expect(date.hour, 15);
      expect(date.minute, 20);
      expect(result.hasTimeOfDay, isTrue);
      expect(
        date.toUtc(),
        zone == 'Asia/Shanghai'
            ? DateTime.utc(2026, 10, 23, 7, 20, 30, 123, 456)
            : DateTime.utc(2026, 10, 23, 19, 20, 30, 123, 456),
      );
    });

    test('UTC and numeric offsets convert into $zone', () async {
      await LocalTimezoneResolver.setApplicationTimeZone(zone);
      for (final text in [
        '2026-10-23T02:30:00Z',
        '2026-10-23T10:30:00+08:00',
        '2026-10-22T22:30:00-0400',
      ]) {
        final result = _parse({'date_time': text, 'has_time': true});
        final date = result!.dateTime!;
        expect(date.toUtc(), DateTime.utc(2026, 10, 23, 2, 30));
        expect(
          (date.year, date.month, date.day, date.hour, date.minute),
          zone == 'Asia/Shanghai'
              ? (2026, 10, 23, 10, 30)
              : (2026, 10, 22, 22, 30),
        );
        expect(result.hasTimeOfDay, isTrue);
      }
    });

    test('date-only never enables a time reminder in $zone', () async {
      await LocalTimezoneResolver.setApplicationTimeZone(zone);
      final result = _parse({'date_time': '2026-10-23', 'has_time': true});
      final date = result!.dateTime!;
      expect((date.year, date.month, date.day, date.hour), (2026, 10, 23, 0));
      expect(date, isNot(isA<tz.TZDateTime>()));
      expect(result.hasTimeOfDay, isFalse);
    });
  }

  test('date-only stays floating across a Santiago midnight DST gap', () async {
    await LocalTimezoneResolver.setApplicationTimeZone('America/Santiago');
    final result = _parse({'date_time': '2026-09-06', 'has_time': false})!;
    expect(result.dateTime, DateTime(2026, 9, 6));
    expect(result.dateTime, isNot(isA<tz.TZDateTime>()));
    expect(result.hasTimeOfDay, isFalse);
  });

  test('usable time requires an explicit boolean has_time flag', () {
    for (final flag in [false, null, 'true', 1]) {
      final result = _parse({
        'date_time': '2026-10-23T00:00:00',
        'has_time': flag,
      });
      expect(result!.dateTime, AppClock.date(2026, 10, 23));
      expect(result.hasTimeOfDay, isFalse);
    }
    expect(
      _parse({
        'date_time': '2026-10-23T00:00:00',
        'has_time': true,
      })!.hasTimeOfDay,
      isTrue,
    );
    expect(
      _parse({'date_time': null, 'has_time': true})!.hasTimeOfDay,
      isFalse,
    );
  });

  test('invalid dates and normalized time values are discarded', () {
    for (final value in <Object?>[
      '2026-02-31',
      '2026-02-29T15:00:00',
      '2026-02-31T15:00:00Z',
      '2026-02-31T15:00:00+08:00',
      '2026-04-31T15:00:00',
      '2026-13-01T15:00:00',
      '2026-00-01T15:00:00',
      '2026-10-00T15:00:00',
      '2026-10-23T24:00:00',
      '2026-10-23T15:60:00',
      '2026-10-23T15:00:60',
      '2026-10-23T15:00:00+24:00',
      '2026-10-23T15:00:00+08:60',
      '2026-10-23T15',
      '',
      20261023,
      {'year': 2026},
    ]) {
      final result = _parse({'date_time': value, 'has_time': true});
      expect(result!.dateTime, isNull, reason: '$value');
      expect(result.hasTimeOfDay, isFalse, reason: '$value');
      expect(result.subtasks, _subtasks);
    }
    expect(
      _parse({'date_time': '2028-02-29T15:00:00'})!.dateTime,
      AppClock.date(2028, 2, 29, 15),
    );
  });

  test('nonexistent New York daylight-saving wall time is discarded', () async {
    await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
    final result = _parse({
      'date_time': '2026-03-08T02:30:00',
      'has_time': true,
    });
    expect(result!.dateTime, isNull);
    expect(result.hasTimeOfDay, isFalse);
  });

  test('legacy breakDownTask keeps its line-based API and cleanup', () async {
    final requests = <http.Request>[];
    final service = _serviceReturning(
      '1. 收集资料\n- 整理提纲\n* 提交文档\n',
      onRequest: requests.add,
    );
    final result = await service.breakDownTask('整理项目资料');
    expect(result, ['收集资料', '整理提纲', '提交文档']);
    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['user'], '整理项目资料');
    expect(body['system'], contains('每条一行'));
  });
}
