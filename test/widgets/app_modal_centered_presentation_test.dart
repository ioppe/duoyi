import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_motion.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/widgets/app_modal_presentation.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Web（含窄屏 Web）与 native macOS 的 `showAppModalSheet` 一律渲染成居中
/// 对话框；native Android / iOS 的底部半屏面板行为由
/// app_modal_sheet_layout_test / extent_test / drag_handle_test 继续覆盖。
///
/// Web 构建由测试开关注入；macOS 使用 TargetPlatformVariant，平台状态由
/// 框架在测试体结束前复位，不依赖晚于不变量检查执行的 tearDown。

void useWebHost() {
  // Web 判定只看构建目标，与宿主 platform 无关。
  WebTarget.debugWebBuild = true;
  addTearDown(() {
    WebTarget.debugWebBuild = null;
  });
}

void useMacHost() {
  expect(defaultTargetPlatform, TargetPlatform.macOS);
  WebTarget.debugWebBuild = false;
  addTearDown(() {
    WebTarget.debugWebBuild = null;
  });
}

/// 上层作用域：验证弹层仍能读到启动方所在的 InheritedWidget。
class _TestScope extends InheritedWidget {
  final String label;

  const _TestScope({required this.label, required super.child});

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TestScope>()?.label ?? '';

  @override
  bool updateShouldNotify(_TestScope oldWidget) => oldWidget.label != label;
}

Finder get _card => find
    .descendant(of: find.byType(AppModalSheet), matching: find.byType(Material))
    .first;

Finder get _closeButton => find.byTooltip(I18n.tr('action.close'));

/// 统计实际绘制出来的“手机拖动手柄”：又扁又短的小色块。
int countDragHandles(WidgetTester tester) {
  var count = 0;
  for (final element in find.byType(Container).evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    final size = box.size;
    if (size.height <= 6 && size.width >= 24 && size.width <= 48) count++;
  }
  return count;
}

Future<void> pumpHost(
  WidgetTester tester, {
  required Size size,
  required WidgetBuilder sheetBuilder,
  double textScale = 1,
  bool disableAnimations = false,
  bool useRootNavigator = false,
  String? label,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
    theme: AppBrands.defaultBrand.theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showAppModalSheet<void>(
              context: context,
              useRootNavigator: useRootNavigator,
              builder: sheetBuilder,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    label == null ? app : _TestScope(label: label, child: app),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Widget simpleSheet({String title = '居中弹窗', double? maxWidth}) => AppModalSheet(
  title: title,
  maxWidth: maxWidth ?? DesignTokens.creationFormMaxWidth,
  child: const Text('简短内容'),
);

void main() {
  testWidgets('Web 1280：居中显示、无底部面板与手柄、宽度取 720 上限', (tester) async {
    useWebHost();
    await pumpHost(
      tester,
      size: const Size(1280, 800),
      sheetBuilder: (_) => simpleSheet(),
    );

    expect(find.byType(AppModalSheet), findsOneWidget);
    // 不再是 BottomSheet，也没有手机拖动手柄。
    expect(find.byType(BottomSheet), findsNothing);
    expect(countDragHandles(tester), 0);

    final rect = tester.getRect(_card);
    // 水平、垂直都居中（四周等边距）。
    expect(rect.center.dx, closeTo(640, 1));
    expect(rect.center.dy, closeTo(400, 1));
    // 默认 creationFormMaxWidth 生效，且不越过视口边距。
    expect(rect.width, closeTo(DesignTokens.creationFormMaxWidth, 1));
    expect(rect.width, lessThan(1280 - 48));
    // 圆角为四角统一档位，不再是只圆上面的 sheet 角。
    final material = tester.widget<Material>(_card);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      BorderRadius.circular(DesignTokens.appModalCenteredRadius),
    );
    expect(material.elevation, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Web 窄屏 320：四周 12 边距、水平垂直居中', (tester) async {
    useWebHost();
    await pumpHost(
      tester,
      size: const Size(320, 720),
      sheetBuilder: (_) => simpleSheet(),
    );

    final rect = tester.getRect(_card);
    expect(rect.left, closeTo(DesignTokens.appModalCenteredNarrowMargin, 1));
    expect(
      rect.right,
      closeTo(320 - DesignTokens.appModalCenteredNarrowMargin, 1),
    );
    expect(rect.center.dx, closeTo(160, 1));
    expect(rect.center.dy, closeTo(360, 1));
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'macOS 平台同样居中（不依赖 kIsWeb）',
    (tester) async {
      useMacHost();
      await pumpHost(
        tester,
        size: const Size(1280, 800),
        sheetBuilder: (_) => simpleSheet(title: 'macOS 弹窗'),
      );

      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final rect = tester.getRect(_card);
      expect(rect.center.dy, closeTo(400, 1));
      expect(countDragHandles(tester), 0);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('特殊面板宽度 860 / 520 原样保留', (tester) async {
    useWebHost();
    for (final width in const [860.0, 520.0]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpHost(
        tester,
        size: const Size(1280, 800),
        sheetBuilder: (_) => simpleSheet(maxWidth: width),
      );
      expect(tester.getRect(_card).width, closeTo(width, 1));
      // 关掉再开下一个宽度，避免两条路由叠在一起。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('长内容在卡片内滚动，固定 actions 始终可点', (tester) async {
    useWebHost();
    var saved = false;
    await pumpHost(
      tester,
      size: const Size(1280, 800),
      sheetBuilder: (_) => AppModalSheet(
        title: '长表单',
        actions: [
          TextButton(onPressed: () => saved = true, child: const Text('保存')),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 40; i++)
              SizedBox(height: 56, child: Text('第 $i 项')),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );

    final maxAllowed =
        (800 - DesignTokens.appModalCenteredMargin * 2) *
        DesignTokens.appModalCenteredMaxHeightFactor;
    final rect = tester.getRect(_card);
    expect(rect.height, lessThanOrEqualTo(maxAllowed + 1));
    expect(rect.height, greaterThan(320));
    // 卡片顶端不再贴住屏幕顶部（内容自适应 + 上限）。
    expect(rect.top, greaterThan(0));

    // 固定 actions 不随内容滚走，直接可点。
    expect(find.text('保存').hitTestable(), findsOneWidget);
    await tester.tap(find.text('保存'));
    expect(saved, isTrue);

    // 内容底部条目滚到可见后仍可点击并关闭。
    await tester.scrollUntilVisible(find.text('完成'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘 300px 且 2 倍字号：卡片让出键盘高度且不溢出', (tester) async {
    useWebHost();
    await pumpHost(
      tester,
      size: const Size(390, 844),
      textScale: 2,
      sheetBuilder: (_) => AppModalSheet(
        title: '窄屏键盘',
        actions: [TextButton(onPressed: () {}, child: const Text('确定'))],
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [TextField(), SizedBox(height: 900)],
        ),
      ),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final rect = tester.getRect(_card);
    // 卡片整体位于键盘上方，且不再二次扣减键盘高度造成溢出。
    expect(rect.bottom, lessThanOrEqualTo(844 - 300 + 1));
    expect(rect.height, greaterThan(0));
    expect(tester.takeException(), isNull);

    // 键盘弹出后操作区仍然可达。
    await tester.ensureVisible(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('确定').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape / 遮罩 / 关闭按钮都能关闭，无重影手柄', (tester) async {
    useWebHost();
    await pumpHost(
      tester,
      size: const Size(1280, 800),
      sheetBuilder: (_) => simpleSheet(),
    );
    expect(_closeButton, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);

    await pumpHost(
      tester,
      size: const Size(1280, 800),
      sheetBuilder: (_) => simpleSheet(),
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);

    await pumpHost(
      tester,
      size: const Size(1280, 800),
      sheetBuilder: (_) => simpleSheet(),
    );
    await tester.tap(_closeButton);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭按钮、Escape 与遮罩尊重内容的 PopScope', (tester) async {
    useWebHost();
    await pumpHost(
      tester,
      size: const Size(1280, 800),
      sheetBuilder: (_) =>
          PopScope(canPop: false, child: simpleSheet(title: '保留草稿')),
    );
    await tester.tap(_closeButton);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('isDismissible=false：不显示关闭按钮，遮罩与 Escape 都不关闭', (tester) async {
    useWebHost();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppModalSheet<void>(
                  context: context,
                  isDismissible: false,
                  builder: (_) => simpleSheet(title: '不可关闭'),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(_closeButton, findsNothing);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('嵌套 picker 只返回内层，外层输入草稿保留', (tester) async {
    useWebHost();
    final draft = TextEditingController();
    addTearDown(draft.dispose);
    String? picked;

    await pumpHost(
      tester,
      size: const Size(1280, 800),
      sheetBuilder: (_) => AppModalSheet(
        title: '外层表单',
        child: StatefulBuilder(
          builder: (outerContext, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: draft),
              Text('已选：${picked ?? '未选择'}'),
              TextButton(
                onPressed: () async {
                  final value = await showAppModalSheet<String>(
                    context: outerContext,
                    builder: (innerContext) => AppModalSheet(
                      title: '内层选择',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final option in const ['A', 'B'])
                            ListTile(
                              title: Text(option),
                              onTap: () =>
                                  Navigator.of(innerContext).pop(option),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (value != null) setState(() => picked = value);
                },
                child: const Text('打开选择'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '草稿内容');
    await tester.tap(find.text('打开选择'));
    await tester.pumpAndSettle();
    expect(find.text('内层选择'), findsOneWidget);
    expect(find.text('外层表单'), findsOneWidget);

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    // 只关掉内层；外层仍在，草稿与已选值都保留。
    expect(find.text('内层选择'), findsNothing);
    expect(find.text('外层表单'), findsOneWidget);
    expect(find.text('已选：B'), findsOneWidget);
    expect(draft.text, '草稿内容');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Navigator 返回值与 useRootNavigator 语义保持不变', (tester) async {
    useWebHost();
    final nestedNavigatorKey = GlobalKey<NavigatorState>();
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Scaffold(
          body: Navigator(
            key: nestedNavigatorKey,
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              builder: (_) => Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showAppModalSheet<String>(
                      context: nestedNavigatorKey.currentContext!,
                      useRootNavigator: true,
                      builder: (sheetContext) => AppModalSheet(
                        title: '根导航弹窗',
                        child: Builder(
                          builder: (innerContext) => TextButton(
                            onPressed: () =>
                                Navigator.of(innerContext).pop('返回值'),
                            child: const Text('返回'),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('根导航弹窗'), findsOneWidget);
    // useRootNavigator: true → 弹层挂在根 Navigator，而不是嵌套 Navigator。
    expect(
      find.descendant(
        of: find.byKey(nestedNavigatorKey),
        matching: find.byType(AppModalSheet),
      ),
      findsNothing,
    );
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(result, '返回值');
    expect(find.byType(AppModalSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹层内仍可读取启动方上层的 InheritedWidget', (tester) async {
    useWebHost();
    await pumpHost(
      tester,
      size: const Size(1280, 800),
      label: '作用域值',
      sheetBuilder: (_) => AppModalSheet(
        title: '作用域',
        child: Builder(builder: (context) => Text(_TestScope.of(context))),
      ),
    );

    expect(find.text('作用域值'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时单帧到位：无缩放过渡、无百分比', (tester) async {
    useWebHost();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppModalSheet<void>(
                  context: context,
                  builder: (_) => simpleSheet(),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    // 只 pump 一帧：减少动画时没有过渡，卡片立即到位。
    await tester.pump();

    expect(find.byType(AppModalSheet), findsOneWidget);
    final rect = tester.getRect(_card);
    expect(rect.center.dy, closeTo(400, 1));
    expect(
      find.ancestor(
        of: find.byType(AppModalCenteredLayout),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byType(AppModalCenteredLayout),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('常规动画：首帧为 0.96 缩放 + 淡入，随后回到 1', (tester) async {
    useWebHost();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: false),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppModalSheet<void>(
                  context: context,
                  builder: (_) => simpleSheet(),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(AppMotion.reduced(tester.element(find.text('打开'))), isFalse);
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(AppModalCenteredLayout), findsOneWidget);

    final scaleTransition = tester.widget<ScaleTransition>(
      find
          .ancestor(
            of: find.byType(AppModalCenteredLayout),
            matching: find.byType(ScaleTransition),
          )
          .first,
    );
    expect(
      scaleTransition.scale.value,
      closeTo(DesignTokens.appModalCenteredScaleBegin, 0.01),
    );
    expect(
      find.ancestor(
        of: find.byType(AppModalCenteredLayout),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
