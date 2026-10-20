import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _card => find
    .descendant(of: find.byType(AppModalSheet), matching: find.byType(Material))
    .first;
Finder get _verticalScroll => find
    .descendant(
      of: find.byType(AppModalSheet),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
      ),
    )
    .first;

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(_verticalScroll).position;

Future<void> _drag(WidgetTester tester, double dy) async {
  final rect = tester.getRect(_verticalScroll);
  await tester.timedDragFrom(
    Offset(rect.left + 8, rect.center.dy),
    Offset(0, dy),
    const Duration(milliseconds: 500),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool scrollable = true,
  Widget? child,
  ScrollController? scrollController,
  List<Widget> actions = const [],
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppBrands.defaultBrand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppModalSheet<void>(
              context: context,
              builder: (context) => AppModalSheet(
                title: '测试弹窗',
                scrollable: scrollable,
                actions: actions,
                scrollController: scrollController,
                child: child ?? const SizedBox(height: 2200),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [Size(320, 720), Size(390, 844), Size(1440, 900)]) {
    testWidgets('$size 浏览时展开，到顶后再次反向拉动收回且保留输入', (tester) async {
      final text = TextEditingController();
      addTearDown(text.dispose);
      var selected = false;
      await _open(
        tester,
        size: size,
        theme: AppBrands.starRail.theme,
        textScale: size.width == 320 ? 1.5 : 1,
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: text),
              CheckboxListTile(
                value: selected,
                onChanged: (value) => setState(() => selected = value!),
                title: const Text('保留选项'),
              ),
              const SizedBox(height: 2200),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      final initial = tester.getRect(_card);
      expect(
        initial.height,
        inInclusiveRange(size.height / 2, size.height * 2 / 3 + 1),
      );
      await tester.enterText(find.byType(TextField), '保留输入');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      for (var cycle = 0; cycle < 2; cycle++) {
        await _drag(tester, -120);
        expect(tester.getRect(_card).height, closeTo(size.height, 1));
        expect(tester.getRect(_card).width, lessThanOrEqualTo(720));
        final beforeScroll = _position(tester).pixels;
        await _drag(tester, -180);
        expect(_position(tester).pixels, greaterThan(beforeScroll));
        // 从内容中部一路返回顶部的这次手势不应同时收回弹窗。
        await _drag(tester, 2800);
        expect(_position(tester).pixels, closeTo(0, 1));
        expect(tester.getRect(_card).height, closeTo(size.height, 1));
        await _drag(tester, 100);
        expect(tester.getRect(_card).height, closeTo(initial.height, 1));
        expect(find.byType(AppModalSheet), findsOneWidget);
        expect(text.text, '保留输入');
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isTrue,
        );
      }
      await _drag(tester, -120);
      await tester.ensureVisible(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('自带列表也可展开并在列表顶部收回，固定操作仍可用', (tester) async {
    var saved = false;
    await _open(
      tester,
      scrollable: false,
      actions: [
        TextButton(onPressed: () => saved = true, child: const Text('应用')),
      ],
      child: SizedBox(
        height: 420,
        child: ListView.builder(
          itemCount: 50,
          itemExtent: 64,
          itemBuilder: (context, index) => Text('选项 $index'),
        ),
      ),
    );
    final initial = tester.getRect(_card).height;
    await _drag(tester, -120);
    expect(tester.getRect(_card).height, closeTo(844, 1));
    expect(tester.getSize(find.byType(ListView)).height, greaterThan(600));
    await _drag(tester, 2800);
    expect(_position(tester).pixels, closeTo(0, 1));
    expect(tester.getRect(_card).height, closeTo(844, 1));
    await _drag(tester, 100);
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    await tester.tap(find.text('应用'));
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横向推荐项和程序定位不会触发展开', (tester) async {
    await _open(
      tester,
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < 12; i++)
                  SizedBox(width: 160, child: Text('推荐 $i')),
              ],
            ),
          ),
          const SizedBox(height: 2200),
        ],
      ),
    );
    final initial = tester.getRect(_card).height;
    await tester.drag(find.byType(ListView), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    _position(tester).jumpTo(200);
    await tester.pumpAndSettle();
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('鼠标滚轮浏览可展开，到顶后再次向回滚动收回', (tester) async {
    await _open(tester);
    final initial = tester.getRect(_card).height;
    Future<void> wheel(double dy) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getRect(_verticalScroll).center,
          scrollDelta: Offset(0, dy),
        ),
      );
      await tester.pumpAndSettle();
    }

    await wheel(120);
    expect(tester.getRect(_card).height, closeTo(844, 1));
    expect(_position(tester).pixels, greaterThan(0));
    await wheel(-2000);
    expect(_position(tester).pixels, closeTo(0, 1));
    expect(tester.getRect(_card).height, closeTo(844, 1));
    await wheel(-80);
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开后避开状态栏和键盘，收回后遮罩仍可关闭', (tester) async {
    await _open(tester);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final initial = tester.getRect(_card).height;
    expect(initial, lessThanOrEqualTo(544 * 2 / 3 + 1));
    await _drag(tester, -120);
    final expanded = tester.getRect(_card);
    expect(expanded.top, closeTo(24, 1));
    expect(expanded.bottom, closeTo(544, 1));
    await _drag(tester, 2800);
    await _drag(tester, 100);
    final collapsed = tester.getRect(_card);
    expect(collapsed.height, closeTo(initial, 1));
    await tester.tapAt(Offset(collapsed.center.dx, collapsed.top - 15));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS 弹性滚动在顶部反向拉动也能收回', (tester) async {
    await _open(
      tester,
      theme: AppBrands.defaultBrand.theme.copyWith(
        platform: TargetPlatform.iOS,
      ),
    );
    final initial = tester.getRect(_card).height;
    await _drag(tester, -120);
    expect(tester.getRect(_card).height, closeTo(844, 1));
    await _drag(tester, 2800);
    expect(tester.getRect(_card).height, closeTo(844, 1));
    await _drag(tester, 100);
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('短内容可拉开并回到原来测得的半屏高度', (tester) async {
    await _open(tester, child: const Text('简短内容'));
    final initial = tester.getRect(_card).height;
    await _drag(tester, -120);
    expect(tester.getRect(_card).height, closeTo(844, 1));
    await _drag(tester, 100);
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('从顶部开始滑离后中途反向不会在内容中部收回', (tester) async {
    await _open(tester);
    await _drag(tester, -120);
    await _drag(tester, 2800);
    final rect = tester.getRect(_verticalScroll);
    final gesture = await tester.startGesture(Offset(rect.left + 8, 400));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, greaterThan(100));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, greaterThan(0));
    expect(tester.getRect(_card).height, closeTo(844, 1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('外部滚动控制器保持连接且支持展开收回', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _open(tester, scrollController: controller);
    final initial = tester.getRect(_card).height;
    await _drag(tester, -120);
    expect(tester.getRect(_card).height, closeTo(844, 1));
    expect(controller.offset, greaterThan(0));
    await _drag(tester, 2800);
    await _drag(tester, 100);
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    expect(controller.hasClients, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自带列表的固定手柄可在顶部收回展开状态', (tester) async {
    await _open(
      tester,
      scrollable: false,
      child: SizedBox(
        height: 420,
        child: ListView(children: const [SizedBox(height: 2200)]),
      ),
    );
    final initial = tester.getRect(_card).height;
    await _drag(tester, -120);
    await _drag(tester, 2800);
    final handle = find
        .descendant(
          of: find.byType(AppModalSheet),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is GestureDetector &&
                widget.onVerticalDragUpdate != null,
          ),
        )
        .first;
    await tester.timedDrag(
      handle,
      const Offset(0, 100),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('列表展开后内容恰好能放下时，仍能从内容区域拉回而非关闭', (tester) async {
    await _open(
      tester,
      scrollable: false,
      theme: AppBrands.defaultBrand.theme.copyWith(
        platform: TargetPlatform.macOS,
      ),
      child: SizedBox(
        height: 420,
        child: ListView.builder(
          itemCount: 8,
          itemExtent: 64,
          itemBuilder: (context, index) => Text('选项 $index'),
        ),
      ),
    );
    final initial = tester.getRect(_card).height;
    await _drag(tester, -120);
    expect(tester.getRect(_card).height, closeTo(844, 1));
    expect(_position(tester).maxScrollExtent, 0);
    expect(
      _position(tester).physics.shouldAcceptUserOffset(_position(tester)),
      isTrue,
    );
    expect(_position(tester).pixels, closeTo(0, 0.5));
    await _drag(tester, 100);
    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('嵌套时间滚轮消费的滚轮事件不能展开或收回外层弹窗', (tester) async {
    final hours = FixedExtentScrollController(initialItem: 12);
    addTearDown(hours.dispose);
    await _open(
      tester,
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: ListWheelScrollView(
              controller: hours,
              itemExtent: 44,
              physics: const FixedExtentScrollPhysics(),
              children: [for (var i = 0; i < 24; i++) Text('$i 时')],
            ),
          ),
          const SizedBox(height: 2200),
        ],
      ),
    );
    final initial = tester.getRect(_card).height;
    Future<void> wheel(double dy) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getRect(find.byType(ListWheelScrollView)).center,
          scrollDelta: Offset(0, dy),
        ),
      );
      await tester.pumpAndSettle();
    }

    await wheel(120);
    expect(hours.selectedItem, greaterThan(12));
    expect(tester.getRect(_card).height, closeTo(initial, 1));
    await _drag(tester, -120);
    await _drag(tester, 2800);
    final before = hours.selectedItem;
    await wheel(-120);
    expect(hours.selectedItem, lessThan(before));
    expect(tester.getRect(_card).height, closeTo(844, 1));
    expect(tester.takeException(), isNull);
  });
}
