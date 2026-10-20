import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/page_tab_style.dart';
import 'package:duoyi/widgets/app_page_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(DesignTokens.fontFamilyRounded)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });

  testWidgets('九套主题共享文字短线页签，窄屏大字不溢出', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final brand in AppBrands.all) {
      for (final width in [320.0, 1280.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('${brand.id}-$width-$scale'),
              theme: brand.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: DefaultTabController(
                length: 2,
                child: Builder(
                  builder: (context) => Scaffold(
                    appBar: AppBar(
                      bottom: AppPageTabs(
                        height: AppPageTabs.heightFor(context),
                        tabs: const [
                          Tab(text: '今日打卡'),
                          Tab(text: '热度图'),
                        ],
                      ),
                    ),
                    body: const TabBarView(
                      children: [Text('today page'), Text('heatmap page')],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final bar = tester.widget<TabBar>(find.byType(TabBar));
          final style = appPageTabTheme(brand.theme);
          expect(bar.isScrollable, isTrue);
          expect(bar.tabAlignment, TabAlignment.start);
          expect(bar.indicatorSize, TabBarIndicatorSize.label);
          expect(bar.indicator, isA<PageTabIndicator>());
          expect(bar.labelColor, style.labelColor);
          expect(bar.unselectedLabelColor, style.unselectedLabelColor);
          expect(bar.labelStyle!.fontSize, 14);
          expect(bar.labelStyle!.fontWeight, FontWeight.w700);
          expect(bar.labelStyle!.fontFamily, DesignTokens.fontFamilyRounded);
          final first = find.widgetWithText(Tab, '今日打卡');
          expect(tester.getSize(first).height, greaterThanOrEqualTo(44));
          expect(tester.getSize(first).width, lessThan(width / 2));
          expect(tester.getTopLeft(first).dx, closeTo(24, 1));
          await tester.tap(find.text('热度图'));
          await tester.pumpAndSettle();
          expect(find.text('heatmap page').hitTestable(), findsOneWidget);
          await tester.drag(find.byType(TabBarView), Offset(width * 0.8, 0));
          await tester.pumpAndSettle();
          expect(find.text('today page').hitTestable(), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '${brand.id} $width x$scale',
          );
        }
      }
    }
  });

  testWidgets('多页签横向滚动可达最后一项，程序控制仍同步', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: DefaultTabController(
          length: 10,
          child: Scaffold(
            appBar: AppBar(
              bottom: AppPageTabs(
                tabs: [for (var i = 0; i < 10; i++) Tab(text: '子页面 $i')],
              ),
            ),
            body: TabBarView(
              children: [for (var i = 0; i < 10; i++) Text('body $i')],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final last = find.widgetWithText(Tab, '子页面 9');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(find.text('body 9').hitTestable(), findsOneWidget);
    final controller = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    controller.animateTo(0);
    await tester.pumpAndSettle();
    expect(find.text('body 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('值驱动视图可点击、外部切换和更新选项且不重复通知', (tester) async {
    var value = 0;
    var count = 2;
    var notifications = 0;
    late StateSetter setParent;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setParent = setState;
            return Scaffold(
              body: AppPageSwitcher<int>(
                value: value,
                options: [
                  for (var i = 0; i < count; i++)
                    AppPageOption(value: i, text: 'view $i'),
                ],
                onChanged: (selected) => setState(() {
                  value = selected;
                  notifications++;
                }),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('view 1'));
    await tester.pumpAndSettle();
    expect(value, 1);
    expect(notifications, 1);
    setParent(() => value = 0);
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    expect(notifications, 1);
    setParent(() {
      count = 3;
      value = 2;
    });
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
    await tester.tap(find.text('view 0'));
    await tester.pumpAndSettle();
    expect(value, 0);
    expect(notifications, 2);
    expect(tester.takeException(), isNull);
  });
}
