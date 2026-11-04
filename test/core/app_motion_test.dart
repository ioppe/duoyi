import 'package:duoyi/core/app_motion.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/widgets/app_page_tabs.dart';
import 'package:duoyi/widgets/app_time_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('系统减少动态效果同步影响反馈、弹层与折叠控件', (tester) async {
    late Duration feedback;
    late AnimationStyle overlay;
    late AnimationStyle expansion;
    final child = Builder(
      builder: (context) {
        feedback = AppMotion.feedback(context);
        overlay = AppMotion.overlayStyle(context);
        expansion = Theme.of(
          context,
        ).expansionTileTheme.expansionAnimationStyle!;
        return const SizedBox();
      },
    );
    await _pump(tester, child);
    expect(feedback, DesignTokens.durationFast);
    expect(overlay.duration, DesignTokens.durationBase);
    expect(expansion.duration, DesignTokens.durationBase);

    await _pump(tester, child, reduced: true);
    expect(feedback, Duration.zero);
    expect(overlay.duration, Duration.zero);
    expect(overlay.reverseDuration, Duration.zero);
    expect(expansion.duration, Duration.zero);

    await _pump(tester, child);
    expect(feedback, DesignTokens.durationFast);
    expect(expansion.duration, DesignTokens.durationBase);
  });

  for (final reduced in [false, true]) {
    testWidgets('桌面页面切换在减少动画=$reduced 时正确显示内容', (tester) async {
      const destination = ValueKey('motion-destination');
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('第二页', key: destination)),
              ),
            ),
            child: const Text('打开页面'),
          ),
        ),
        reduced: reduced,
      );
      await tester.tap(find.text('打开页面'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final fades = find.ancestor(
        of: find.byKey(destination),
        matching: find.byType(Opacity),
      );
      if (reduced) {
        expect(fades, findsNothing);
      } else {
        final opacity = tester.widget<Opacity>(fades.first).opacity;
        expect(opacity, greaterThan(0));
        expect(opacity, lessThan(1));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(destination).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final reduced in [false, true]) {
    testWidgets('减少动画=$reduced 时保留 iOS 边缘返回手势', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('原生次页')),
                  body: const Center(child: Text('可滑动返回')),
                ),
              ),
            ),
            child: const Text('打开原生次页'),
          ),
        ),
        reduced: reduced,
        platform: TargetPlatform.iOS,
      );
      await tester.tap(find.text('打开原生次页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final initialPosition = tester.getTopLeft(find.text('可滑动返回'));
      await tester.pumpAndSettle();
      if (reduced) {
        expect(tester.getTopLeft(find.text('可滑动返回')), initialPosition);
      }
      await tester.timedDragFrom(
        const Offset(1, 300),
        const Offset(650, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(find.text('可滑动返回'), findsNothing);
      expect(find.text('打开原生次页').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final systemBack in [false, true]) {
    testWidgets('Android ${systemBack ? '系统' : '标题栏'}返回只横移且不缩放', (
      tester,
    ) async {
      await _openAndroidPage(tester);
      final page = find.byKey(_androidPage);
      final original = tester.getRect(page);
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        final back = tester.getCenter(find.byType(BackButton));
        final canceled = await tester.startGesture(back);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.getRect(page), original, reason: '按住返回按钮时页面不退出');
        await canceled.moveBy(const Offset(0, 120));
        await canceled.up();
        await tester.pumpAndSettle();
        expect(tester.getRect(page), original, reason: '拖出按钮再松开应取消返回');

        final released = await tester.startGesture(back);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.getRect(page), original);
        await released.up();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final frame = tester.getRect(page);
      expect(frame.left, greaterThan(original.left));
      expect(frame.top, original.top);
      expect(frame.size, original.size);
      expect(tester.getTopLeft(find.text('打开安卓次页')), Offset.zero);
      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(find.text('打开安卓次页').hitTestable(), findsOneWidget);
    });
  }

  testWidgets('Android 侧滑按住不移动，滑回取消，松手确认后才横移', (tester) async {
    final navigator = await _openAndroidPage(tester);
    final page = find.byKey(_androidPage);
    final original = tester.getRect(page);
    final route = ModalRoute.of(tester.element(page))!;

    void expectStationary() {
      expect(route.isCurrent, isTrue);
      expect(tester.getRect(page), original);
    }

    Future<void> dragAndHold() async {
      await _sendBackGesture(tester, 'startBackGesture', _backEvent(0.05));
      await tester.pump();
      expect(navigator.userGestureInProgress, isTrue);
      expectStationary();

      await _sendBackGesture(
        tester,
        'updateBackGestureProgress',
        _backEvent(0.9),
      );
      await tester.pump();
      expectStationary();
      await tester.pump(const Duration(milliseconds: 300));
      expectStationary();
    }

    await dragAndHold();
    await _sendBackGesture(tester, 'updateBackGestureProgress', _backEvent(0));
    await tester.pump();
    expectStationary();
    await _sendBackGesture(tester, 'cancelBackGesture');
    await tester.pump();
    expectStationary();
    expect(navigator.userGestureInProgress, isFalse);
    await tester.pumpAndSettle();
    expectStationary();

    await dragAndHold();
    await _sendBackGesture(tester, 'commitBackGesture');
    await tester.pump();
    expect(tester.getRect(page), original);
    await tester.pump(const Duration(milliseconds: 40));
    final frame = tester.getRect(page);
    expect(frame.left, greaterThan(original.left));
    expect(frame.top, original.top);
    expect(frame.size, original.size);
    expect(tester.getTopLeft(find.text('打开安卓次页')), Offset.zero);
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.text('打开安卓次页').hitTestable(), findsOneWidget);
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('Android 减少动效时预测手势仍可返回且页面不移动', (tester) async {
    final navigator = await _openAndroidPage(tester, reduced: true);
    final page = find.byKey(_androidPage);
    final original = tester.getRect(page);
    await _sendBackGesture(tester, 'startBackGesture', _backEvent(0));
    expect(navigator.userGestureInProgress, isTrue);
    await _sendBackGesture(
      tester,
      'updateBackGestureProgress',
      _backEvent(0.4),
    );
    await tester.pump();
    expect(tester.getRect(page), original);
    await _sendBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('Android 预测返回遵守页面的 PopScope', (tester) async {
    final navigator = await _openAndroidPage(tester, canPop: false);
    final page = find.byKey(_androidPage);
    final original = tester.getRect(page);
    await _sendBackGesture(tester, 'startBackGesture', _backEvent(0));
    expect(navigator.userGestureInProgress, isFalse);
    await _sendBackGesture(
      tester,
      'updateBackGestureProgress',
      _backEvent(0.4),
    );
    await _sendBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(tester.getRect(page), original);
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('Android 侧滑期间禁止退出时提交不返回也不移动', (tester) async {
    final canPop = ValueNotifier(true);
    addTearDown(canPop.dispose);
    final navigator = await _openAndroidPage(tester, popAllowed: canPop);
    final page = find.byKey(_androidPage);
    final original = tester.getRect(page);
    await _sendBackGesture(tester, 'startBackGesture', _backEvent(0));
    expect(navigator.userGestureInProgress, isTrue);
    await _sendBackGesture(
      tester,
      'updateBackGestureProgress',
      _backEvent(0.4),
    );
    await tester.pump();
    expect(tester.getRect(page), original);

    canPop.value = false;
    await tester.pump();
    await _sendBackGesture(tester, 'commitBackGesture');
    await tester.pump();
    expect(tester.getRect(page), original);
    await tester.pumpAndSettle();
    expect(tester.getRect(page), original);
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('分页在设置变化后保留选择并可立即切换', (tester) async {
    var selected = 0;
    Widget switcher() => StatefulBuilder(
      builder: (context, setState) => AppPageSwitcher<int>(
        options: const [
          AppPageOption(value: 0, text: '今日'),
          AppPageOption(value: 1, text: '统计'),
        ],
        value: selected,
        onChanged: (value) => setState(() => selected = value),
      ),
    );
    await _pump(tester, switcher());
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    await _pump(tester, switcher(), reduced: true);
    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.controller!.index, 1);
    await tester.tap(find.text('今日'));
    await tester.pump();
    expect(selected, 0);
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).controller!.indexIsChanging,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时选择时间预设与确认仍可用', (tester) async {
    TimeOfDay? result;
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await AppTimePicker.show(
              context,
              initialTime: const TimeOfDay(hour: 9, minute: 15),
            );
          },
          child: const Text('打开时间'),
        ),
      ),
      reduced: true,
    );
    await tester.tap(find.text('打开时间'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('晚上 20:00'));
    await tester.tap(find.text('晚上 20:00'));
    await tester.pump();
    await tester.ensureVisible(find.text('确定'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, const TimeOfDay(hour: 20, minute: 0));
    expect(tester.takeException(), isNull);
  });
}

const _androidPage = ValueKey('motion-android-page');

Future<NavigatorState> _openAndroidPage(
  WidgetTester tester, {
  bool reduced = false,
  bool canPop = true,
  ValueListenable<bool>? popAllowed,
}) async {
  late NavigatorState navigator;
  await _pump(
    tester,
    Builder(
      builder: (context) {
        navigator = Navigator.of(context);
        return GestureDetector(
          onTap: () => navigator.push(
            MaterialPageRoute<void>(
              builder: (_) {
                final page = Scaffold(key: _androidPage, appBar: AppBar());
                if (popAllowed == null) {
                  return PopScope(canPop: canPop, child: page);
                }
                return ValueListenableBuilder<bool>(
                  valueListenable: popAllowed,
                  child: page,
                  builder: (_, allowed, child) =>
                      PopScope(canPop: allowed, child: child!),
                );
              },
            ),
          ),
          child: const Text('打开安卓次页'),
        );
      },
    ),
    platform: TargetPlatform.android,
    reduced: reduced,
  );
  await tester.tap(find.text('打开安卓次页'));
  await tester.pumpAndSettle();
  return navigator;
}

Map<String, Object> _backEvent(double progress) => {
  'touchOffset': <double>[5 + 200 * progress, 300],
  'progress': progress,
  'swipeEdge': 0,
};

Future<void> _sendBackGesture(
  WidgetTester tester,
  String method, [
  Map<String, Object>? arguments,
]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
  'flutter/backgesture',
  const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
  (_) {},
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
  TargetPlatform platform = TargetPlatform.linux,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: ThemeData(
        platform: platform,
        pageTransitionsTheme: AppMotion.pageTransitions,
        expansionTileTheme: const ExpansionTileThemeData(
          expansionAnimationStyle: AppMotion.expansionStyle,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: Builder(
          builder: (context) => Theme(
            data: AppMotion.themeFor(context, Theme.of(context)),
            child: child!,
          ),
        ),
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
