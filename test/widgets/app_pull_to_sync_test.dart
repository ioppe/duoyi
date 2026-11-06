import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/sync_status_presenter.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/app_pull_to_sync.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  SyncStatusController? controller,
}) => tester.pumpWidget(
  ChangeNotifierProvider<SyncStatusController?>.value(
    value: controller,
    child: MaterialApp(
      home: Scaffold(body: AppPullToSync(child: child)),
    ),
  ),
);

Future<void> _pull(WidgetTester tester, Finder target) async {
  await tester.drag(target, const Offset(0, 350));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('空白内容下拉触发同步，等待真实完成后才收起转圈', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    final controller = SyncStatusController(
      onSyncRequested: () {
        calls++;
        return gate.future;
      },
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      const Center(child: Text('empty')),
      controller: controller,
    );

    await _pull(tester, find.text('empty'));
    expect(calls, 1);
    expect(controller.isSyncing, isTrue);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    await _pull(tester, find.text('empty'));
    expect(calls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.isSyncing, isFalse);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('不足一屏的列表也可下拉同步', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async => calls++,
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      ListView(children: const [ListTile(title: Text('short list'))]),
      controller: controller,
    );
    await _pull(tester, find.byType(ListView));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横向标签页内的纵向列表支持同步，横滑不触发', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async => calls++,
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      PageView(
        children: [
          ListView(children: const [ListTile(title: Text('first tab'))]),
          ListView(children: const [ListTile(title: Text('second tab'))]),
        ],
      ),
      controller: controller,
    );
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('second tab').hitTestable(), findsOneWidget);
    await _pull(tester, find.text('second tab'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('列表中部向下浏览不会发起同步', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async => calls++,
    );
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await _pump(
      tester,
      ListView.builder(
        controller: scroll,
        itemCount: 100,
        itemExtent: 60,
        itemBuilder: (_, index) => Text('row $index'),
      ),
      controller: controller,
    );
    scroll.jumpTo(1200);
    await tester.pump();
    await _pull(tester, find.byType(ListView));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('页面未回到顶部时，内层列表到顶也不会误同步', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async => calls++,
    );
    final outer = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(outer.dispose);
    await _pump(
      tester,
      ListView(
        controller: outer,
        children: [
          const SizedBox(height: 200),
          SizedBox(
            height: 300,
            child: ListView(
              key: const ValueKey('inner-list'),
              children: const [Text('nested list')],
            ),
          ),
          const SizedBox(height: 1200),
        ],
      ),
      controller: controller,
    );
    outer.jumpTo(150);
    await tester.pump();
    await _pull(tester, find.byKey(const ValueKey('inner-list')));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('同步失败给出可重试提示且不暴露异常文本', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async {
        calls++;
        if (calls == 1) throw StateError('private-token-and-server');
      },
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      const Center(child: Text('retry')),
      controller: controller,
    );
    await _pull(tester, find.text('retry'));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('sync.state.failed')), findsOneWidget);
    expect(find.textContaining('private-token'), findsNothing);
    expect(controller.syncRequestFailed, isTrue);

    await _pull(tester, find.text('retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(controller.syncRequestFailed, isFalse);
  });

  testWidgets('二级页面通过共用路由表面接入，标题栏位置不变', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async => calls++,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SyncStatusController>.value(value: controller),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: BrandRouteSurface(
            child: Scaffold(
              appBar: AppBar(title: const Text('secondary title')),
              body: ListView(children: const [Text('secondary content')]),
            ),
          ),
        ),
      ),
    );
    final titlePosition = tester.getTopLeft(find.text('secondary title'));
    await _pull(tester, find.text('secondary content'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.getTopLeft(find.text('secondary title')), titlePosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同步在途离开页面后不显示过期提示', (tester) async {
    final gate = Completer<void>();
    final controller = SyncStatusController(onSyncRequested: () => gate.future);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      const Center(child: Text('leave page')),
      controller: controller,
    );
    await _pull(tester, find.text('leave page'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    gate.completeError(StateError('private error'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未注入同步入口时保留原始页面', (tester) async {
    await _pump(tester, const Text('no controller'));
    expect(find.byType(RefreshIndicator), findsNothing);
    final controller = SyncStatusController();
    addTearDown(controller.dispose);
    await _pump(tester, const Text('no action'), controller: controller);
    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('桌面平台不添加下拉刷新手势', (tester) async {
    var calls = 0;
    final controller = SyncStatusController(
      onSyncRequested: () async => calls++,
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      ListView(children: const [Text('desktop')]),
      controller: controller,
    );
    expect(find.byType(RefreshIndicator), findsNothing);
    await tester.drag(find.text('desktop'), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(calls, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
