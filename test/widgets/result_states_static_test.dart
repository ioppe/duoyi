import 'dart:io';

import 'package:duoyi/widgets/empty_state.dart';
import 'package:duoyi/widgets/result_states.dart' show ErrorState, LoadingState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('result_states.dart 统一导出 EmptyState/LoadingState/ErrorState', () {
    final source = File('lib/widgets/result_states.dart').readAsStringSync();
    final emptyState = File('lib/widgets/empty_state.dart').readAsStringSync();
    final auditor = File(
      'lib/core/empty_surface_auditor.dart',
    ).readAsStringSync();
    final checklist = File('docs/empty-surface-audit.md').readAsStringSync();
    final router = File(
      'lib/screens/today_detail_router.dart',
    ).readAsStringSync();

    expect(source, contains("export 'empty_state.dart' show EmptyState;"));
    expect(source, contains('class LoadingState extends StatefulWidget'));
    expect(source, contains('class ErrorState extends StatelessWidget'));
    expect(source, contains('AnimationController'));
    expect(source, contains('ShaderMask'));
    expect(emptyState, contains('FilledButton.tonalIcon'));
    expect(source, contains('return EmptyState('));
    expect(source, contains('actionIcon: Icons.refresh'));
    expect(source, contains("title = '出错了'"));

    expect(emptyState, contains('class EmptyState extends StatelessWidget'));
    expect(auditor, contains("file: 'lib/widgets/result_states.dart'"));
    expect(auditor, contains('EmptyState / LoadingState / ErrorState 三件套已实现'));
    expect(auditor, contains("fixTicketId: '20'"));
    expect(checklist, contains('| `lib/widgets/result_states.dart` |'));
    expect(
      checklist,
      contains('`EmptyState / LoadingState / ErrorState` 三件套已实现并统一导出'),
    );
    expect(checklist, contains('✅ **20**'));
    expect(router, isNot(contains('Task 20 会补齐')));
  });

  test('空架子审计清单没有未闭环条目', () {
    final auditor = File(
      'lib/core/empty_surface_auditor.dart',
    ).readAsStringSync();
    final checklist = File('docs/empty-surface-audit.md').readAsStringSync();
    final entryPattern = RegExp(r'EmptySurfaceEntry\((.*?)\),', dotAll: true);
    final openEntries = [
      for (final match in entryPattern.allMatches(auditor))
        if (!match.group(1)!.contains('fixTicketId:')) match.group(1)!,
    ];

    expect(
      openEntries,
      isEmpty,
      reason:
          'EmptySurfaceAuditor.known should not keep untracked empty surfaces.',
    );
    expect(
      auditor,
      contains('known.where((e) => e.fixTicketId == null)'),
      reason:
          'openEntries must continue to define unfinished items as missing fixTicketId.',
    );
    expect(
      auditor,
      contains('element.visitChildElements(visit)'),
      reason:
          'runtimeAudit should actively inspect the current widget tree instead of returning an empty placeholder report.',
    );
    expect(auditor, contains('widget is Text'));
    expect(auditor, contains('_looksLikePlaceholderText'));
    expect(auditor, isNot(contains('运行时探测占位（当前为占位实现）')));
    expect(auditor, isNot(contains('留接口不留实现')));
    final unfinishedRows = checklist
        .split('\n')
        .where((line) => line.trimLeft().startsWith('|') && line.contains('⏳'))
        .toList(growable: false);
    expect(
      unfinishedRows,
      isEmpty,
      reason:
          'docs/empty-surface-audit.md should not list unfinished table rows before patch release.',
    );
  });

  testWidgets('EmptyState fits inside a 200px container', (tester) async {
    await _pumpConstrained(
      tester,
      width: 200,
      child: EmptyState(
        icon: Icons.inbox_outlined,
        message: '这里是一段很长的空状态说明文字，需要在极窄容器中保持可读且不撑破边框',
        actionLabel: '创建一个新的长期目标',
        onAction: () {},
      ),
    );

    expect(find.byType(EmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LoadingState and ErrorState fit inside 200-320px containers', (
    tester,
  ) async {
    await _pumpConstrained(
      tester,
      width: 200,
      child: const LoadingState(message: '正在加载一段比较长的结果状态说明', lines: 4),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(LoadingState), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpConstrained(
      tester,
      width: 320,
      child: ErrorState(
        title: '同步结果加载失败',
        error: '这是一段很长的错误信息，用于验证结果状态在窄屏下不会横向溢出',
        onRetry: () {},
      ),
    );

    expect(find.byType(ErrorState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpConstrained(
  WidgetTester tester, {
  required double width,
  required Widget child,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 520));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}
