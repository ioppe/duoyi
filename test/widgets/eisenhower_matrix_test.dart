import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/eisenhower_matrix.dart';

Widget _wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

TodoItem _todo(String id, EisenhowerQuadrant quadrant) =>
    TodoItem(id: id, title: '任务-$id', quadrant: quadrant);

Future<void> _longPressDrag(
  WidgetTester tester,
  Finder from,
  Offset delta,
) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  // 越过 LongPressDraggable 的长按阈值，进入拖拽状态。
  await tester.pump(const Duration(milliseconds: 500));
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('四象限标题使用红紫黄绿的共享语义色', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: const {},
            onQuadrantTap: (_) {},
          ),
        ),
      ),
    );
    final strings = ThemeProvider().brand.strings;
    for (final (label, color) in [
      (strings.quadrantQ1Label, const Color(0xFFE53935)),
      (strings.quadrantQ2Label, const Color(0xFF8E5CC6)),
      (strings.quadrantQ3Label, const Color(0xFFF6A339)),
      (strings.quadrantQ4Label, const Color(0xFF43A047)),
    ]) {
      expect(tester.widget<Text>(find.text(label)).style?.color, color);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按拖动待办到目标象限触发 onTodoQuadrantChanged', (tester) async {
    final todoA = _todo('a', EisenhowerQuadrant.urgentImportant);
    final moves = <(TodoItem, EisenhowerQuadrant)>[];

    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: {
              EisenhowerQuadrant.urgentImportant: [todoA],
            },
            onQuadrantTap: (_) {},
            onTodoQuadrantChanged: (todo, target) => moves.add((todo, target)),
          ),
        ),
      ),
    );

    // Q1 在左上，垂直下移落入第二行的 Q3（紧急不重要）。
    await _longPressDrag(tester, find.text('任务-a'), const Offset(0, 190));

    expect(moves, hasLength(1));
    expect(moves.single.$1.id, 'a');
    expect(moves.single.$2, EisenhowerQuadrant.urgentNotImportant);
  });

  testWidgets('拖到原象限不触发回调（DragTarget 拒绝同象限）', (tester) async {
    final todoA = _todo('a', EisenhowerQuadrant.urgentImportant);
    var moves = 0;

    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: {
              EisenhowerQuadrant.urgentImportant: [todoA],
            },
            onQuadrantTap: (_) {},
            onTodoQuadrantChanged: (_, _) => moves++,
          ),
        ),
      ),
    );

    // 同行右移落在 Q2（重要不紧急）？不——本用例拖到自身象限：
    // 水平小幅移动后落回 Q1 自身卡片。
    await _longPressDrag(tester, find.text('任务-a'), const Offset(8, 4));

    expect(moves, 0, reason: '同象限投放应被 onWillAcceptWithDetails 拒绝');
  });

  testWidgets('未传回调时矩阵保持只读，长按不进入拖拽也不崩', (tester) async {
    final todoA = _todo('a', EisenhowerQuadrant.urgentImportant);
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: {
              EisenhowerQuadrant.urgentImportant: [todoA],
            },
            onQuadrantTap: (_) {},
          ),
        ),
      ),
    );

    await _longPressDrag(tester, find.text('任务-a'), const Offset(0, 190));

    expect(tester.takeException(), isNull);
  });

  testWidgets('点按象限卡仍触发 onQuadrantTap 进入列表', (tester) async {
    final taps = <EisenhowerQuadrant>[];
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: const {},
            onQuadrantTap: taps.add,
            onTodoQuadrantChanged: (_, _) {},
          ),
        ),
      ),
    );

    // Q3 的标题文案只在该卡出现（subLabel 用词不同）。
    final s = ThemeProvider().brand.strings;
    await tester.tap(find.text(s.quadrantQ3Label));
    await tester.pump();

    expect(taps, [EisenhowerQuadrant.urgentNotImportant]);
  });

  testWidgets('canEditTodo 返回 false 时行不可拖拽，投放不触发回调', (tester) async {
    // 只读共享工作区成员：与 tile 级入口一致，拖拽换象限必须被拦下。
    final todoA = _todo('a', EisenhowerQuadrant.urgentImportant);
    var moves = 0;

    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: {
              EisenhowerQuadrant.urgentImportant: [todoA],
            },
            onQuadrantTap: (_) {},
            canEditTodo: (_) => false,
            onTodoQuadrantChanged: (_, _) => moves++,
          ),
        ),
      ),
    );

    expect(
      find.byType(LongPressDraggable<TodoItem>),
      findsNothing,
      reason: '无编辑权限的行不应包 LongPressDraggable',
    );
    await _longPressDrag(tester, find.text('任务-a'), const Offset(0, 190));

    expect(moves, 0, reason: '只读成员拖拽不得触发换象限');
  });

  testWidgets('canEditTodo 返回 true 时拖拽行为与默认一致', (tester) async {
    final todoA = _todo('a', EisenhowerQuadrant.urgentImportant);
    final moves = <(TodoItem, EisenhowerQuadrant)>[];

    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: {
              EisenhowerQuadrant.urgentImportant: [todoA],
            },
            onQuadrantTap: (_) {},
            canEditTodo: (_) => true,
            onTodoQuadrantChanged: (todo, target) => moves.add((todo, target)),
          ),
        ),
      ),
    );

    await _longPressDrag(tester, find.text('任务-a'), const Offset(0, 190));

    expect(moves, hasLength(1));
    expect(moves.single.$2, EisenhowerQuadrant.urgentNotImportant);
  });

  testWidgets('textScaler 2.0：卡高按 1.6 倍封顶放大，预览不再底部溢出', (tester) async {
    // 4 条任务覆盖「+N 更多」分支：曾因固定行高 24 在大字号下
    // 低估实际行高，预览列底部溢出渲染黄黑警示条。
    final todos = List.generate(
      4,
      (i) => _todo('t$i', EisenhowerQuadrant.notUrgentImportant),
    );
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: {
              EisenhowerQuadrant.notUrgentImportant: todos,
              EisenhowerQuadrant.urgentImportant: [
                _todo('a', EisenhowerQuadrant.urgentImportant),
              ],
            },
            onQuadrantTap: (_) {},
          ),
        ),
        textScaler: TextScaler.linear(2.0),
      ),
    );

    expect(tester.takeException(), isNull);
    // 卡高 160 × 封顶倍率 1.6 = 256；仍钉在 160 时大字号即溢出。
    expect(
      tester.getSize(find.byType(GestureDetector).first).height,
      moreOrLessEquals(256),
    );
    // 预览行高随字号放大后仍按行数推导，未览部分进「更多」标签。
    expect(find.textContaining('更多'), findsOneWidget);
  });

  testWidgets('textScaler 2.0：空象限空态在 Expanded 内自适应，不溢出', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: const {},
            onQuadrantTap: (_) {},
          ),
        ),
        textScaler: TextScaler.linear(2.0),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('暂无任务'), findsNWidgets(4));
    expect(
      tester.getSize(find.byType(GestureDetector).first).height,
      moreOrLessEquals(256),
    );
  });

  testWidgets('textScaler 1.0：卡高保持 160，与基线一致无回归', (tester) async {
    final todos = List.generate(
      4,
      (i) => _todo('t$i', EisenhowerQuadrant.notUrgentImportant),
    );
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: {EisenhowerQuadrant.notUrgentImportant: todos},
            onQuadrantTap: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(GestureDetector).first).height,
      moreOrLessEquals(160),
    );
    expect(find.textContaining('更多'), findsOneWidget);
  });

  testWidgets('fourColumn：四象限单行横排，总高一排 160', (tester) async {
    final s = ThemeProvider().brand.strings;
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: const {},
            onQuadrantTap: (_) {},
            fourColumn: true,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // 单行横排：矩阵总高 = 一排卡高 160（默认 2×2 竖排为 328）。
    expect(
      tester.getSize(find.byType(EisenhowerMatrix)).height,
      moreOrLessEquals(160),
    );
    final q1 = tester.getCenter(find.text(s.quadrantQ1Label));
    final q2 = tester.getCenter(find.text(s.quadrantQ2Label));
    final q3 = tester.getCenter(find.text(s.quadrantQ3Label));
    final q4 = tester.getCenter(find.text(s.quadrantQ4Label));
    expect(q1.dy, moreOrLessEquals(q2.dy));
    expect(q1.dy, moreOrLessEquals(q3.dy));
    expect(q1.dy, moreOrLessEquals(q4.dy));
    expect(q2.dx, greaterThan(q1.dx));
    expect(q3.dx, greaterThan(q2.dx));
    expect(q4.dx, greaterThan(q3.dx));
  });
}
