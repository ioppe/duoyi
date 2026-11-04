import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/habit_weekly_card.dart';

/// 固定应用墙钟：2026-03-11 是周三，周一是 2026-03-09。
final DateTime _fixedNow = DateTime(2026, 3, 11, 9, 15);
const int _todayDOW = 2;

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final Finder _card = find.byKey(const ValueKey('habit_weekly_overview_card'));

Rect _contentRect(WidgetTester tester) {
  // AppSurfaceCard 的 render box 含 margin(12) + padding(12)。
  final rect = tester.getRect(_card);
  return Rect.fromLTRB(rect.left + 24, rect.top, rect.right - 24, rect.bottom);
}

List<Rect> _dayRects(WidgetTester tester) => [
  for (var i = 0; i < 7; i++)
    tester.getRect(find.byKey(ValueKey('habit_weekly_overview_day_$i'))),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    AppClock.debugNow = () => _fixedNow;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    AppClock.debugNow = null;
  });

  Future<HabitProvider> weekProvider() async {
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(
        id: 'read',
        name: '阅读',
        icon: Icons.book.codePoint.toString(),
        startDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        completions: {
          _dateKey(DateTime(2026, 3, 9)): 1,
          _dateKey(DateTime(2026, 3, 10)): 1,
        },
      ),
    );
    // 周一、周二满分，今天（周三）0：两个历史 100% 日 + 今天 0%。
    final week = provider.currentWeekProgress();
    expect(week.sublist(0, 3), [1.0, 1.0, 0.0]);
    return provider;
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required Size logicalSize,
    required double devicePixelRatio,
    required double textScale,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(
      logicalSize.width * devicePixelRatio,
      logicalSize.height * devicePixelRatio,
    );
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    final provider = await weekProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          theme: theme ?? AppBrands.defaultBrand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignTokens.habitWorkspaceMaxWidth,
                ),
                child: const SingleChildScrollView(child: HabitWeeklyCard()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 每个百分比文字必须是完整的 RenderParagraph（没有被省略号截断）。
  void expectPercentComplete(WidgetTester tester, List<Rect> dayRects) {
    const expected = ['100%', '100%', '0%', '–', '–', '–', '–'];
    for (var i = 0; i < 7; i++) {
      final valueFinder = find.byKey(
        ValueKey('habit_weekly_overview_value_$i'),
      );
      expect(tester.widget<Text>(valueFinder).data, expected[i]);
      final paragraph = tester.renderObject<RenderParagraph>(valueFinder);
      expect(paragraph.didExceedMaxLines, isFalse, reason: '第 $i 天的百分比被截断');
      final valueRect = tester.getRect(valueFinder);
      expect(
        valueRect.width,
        lessThanOrEqualTo(dayRects[i].width + 0.5),
        reason: '第 $i 天的百分比超出格子',
      );
      expect(
        valueRect.left,
        greaterThanOrEqualTo(dayRects[i].left - 0.5),
        reason: '第 $i 天的百分比溢出格子左边',
      );
      expect(
        valueRect.right,
        lessThanOrEqualTo(dayRects[i].right + 0.5),
        reason: '第 $i 天的百分比溢出格子右边',
      );
      expect(
        valueRect.bottom,
        lessThanOrEqualTo(dayRects[i].bottom + 0.5),
        reason: '第 $i 天的百分比被格子底边裁掉',
      );
    }
  }

  for (final theme in [
    AppBrands.defaultBrand.theme,
    AppBrands.starRail.theme,
  ]) {
    for (final (label, size, dpr, scale) in [
      ('369.23dp 1.25', const Size(369.23, 821.5), 1.0, 1.25),
      ('390dp 1.0', const Size(390, 844), 1.0, 1.0),
      ('320dp 1.0', const Size(320, 720), 1.0, 1.0),
    ]) {
      testWidgets('${theme.brightness} $label 七日格等宽铺满且不再留大空隙', (tester) async {
        await pumpCard(
          tester,
          logicalSize: size,
          devicePixelRatio: dpr,
          textScale: scale,
          theme: theme,
        );

        expect(_card, findsOneWidget);
        expect(
          find.descendant(of: _card, matching: find.byType(FittedBox)),
          findsNothing,
          reason: '不允许用 FittedBox 缩字',
        );

        final rects = _dayRects(tester);
        final content = _contentRect(tester);
        final tileWidth = rects.first.width;
        for (var i = 0; i < 7; i++) {
          expect(rects[i].width, closeTo(tileWidth, 0.5), reason: 'day $i 宽度');
          expect(
            rects[i].height,
            closeTo(rects.first.height, 0.5),
            reason: 'day $i 高度',
          );
          expect(
            rects[i].top,
            closeTo(rects.first.top, 0.5),
            reason: 'day $i 顶部',
          );
        }

        // 放得下就铺满：首格贴内容区左边、末格贴右边，不出现 spaceBetween 空隙。
        expect(rects.first.left, closeTo(content.left, 1));
        expect(rects.last.right, closeTo(content.right, 1));
        expect(
          7 * tileWidth + 6 * 3,
          greaterThan(content.width * 0.97),
          reason: '七日格应填满大部分横宽',
        );

        expectPercentComplete(tester, rects);

        // 达标是语义绿，未达标和未来日期使用不同深浅的中性灰。
        BoxDecoration decoration(int i) =>
            tester
                    .widget<Container>(
                      find.byKey(ValueKey('habit_weekly_overview_day_$i')),
                    )
                    .decoration
                as BoxDecoration;
        final completedFill = decoration(0).color;
        final todayFill = decoration(_todayDOW).color;
        final futureFill = decoration(6).color;
        expect(
          completedFill,
          Color.alphaBlend(
            (theme.brightness == Brightness.dark
                    ? DesignTokens.habitCompletedDark
                    : DesignTokens.habitCompletedLight)
                .withValues(alpha: 0.15),
            theme.colorScheme.surface,
          ),
        );
        expect(
          todayFill,
          Color.alphaBlend(
            DesignTokens.habitPendingTint.withValues(alpha: 0.15),
            theme.colorScheme.surface,
          ),
        );
        expect(
          futureFill,
          Color.alphaBlend(
            DesignTokens.habitPendingTint.withValues(alpha: 0.055),
            theme.colorScheme.surface,
          ),
        );
        expect(todayFill, isNot(completedFill));
        expect(futureFill, isNot(todayFill));
        expect(decoration(0).shape, BoxShape.rectangle);

        final percent = tester.widget<Text>(
          find.byKey(const ValueKey('habit_weekly_overview_percent')),
        );
        // 周一、周二满分，今天 0：本周平均 2/3 -> 67%。
        expect(percent.data, '67%');
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byKey(
                  const ValueKey('habit_weekly_overview_progress_bar'),
                ),
              )
              .value,
          closeTo(2 / 3, 0.001),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('369dp 1.25 字号七日格宽约 40-44dp，不靠滚动也不裁字', (tester) async {
    await pumpCard(
      tester,
      logicalSize: const Size(369.23, 821.5),
      devicePixelRatio: 1,
      textScale: 1.25,
    );
    expect(
      find.descendant(of: _card, matching: find.byType(SingleChildScrollView)),
      findsNothing,
      reason: '1.25 字号下七格必须全部放下，不应滚动',
    );
    final rects = _dayRects(tester);
    expect(rects.first.width, inInclusiveRange(36, 48));
    expect(rects.first.height, greaterThan(48));
    expectPercentComplete(tester, rects);
  });

  testWidgets('821.5dp 宽屏 1.25 字号七日格仍等宽铺满', (tester) async {
    await pumpCard(
      tester,
      logicalSize: const Size(821.5, 700),
      devicePixelRatio: 1,
      textScale: 1.25,
    );
    final rects = _dayRects(tester);
    final content = _contentRect(tester);
    expect(rects.first.left, closeTo(content.left, 1));
    expect(rects.last.right, closeTo(content.right, 1));
    expect(rects.first.width, closeTo((content.width - 18) / 7, 0.5));
    expectPercentComplete(tester, rects);
  });

  testWidgets('320dp 2 倍字号保留完整百分比并允许横向滚动', (tester) async {
    await pumpCard(
      tester,
      logicalSize: const Size(320, 720),
      devicePixelRatio: 1,
      textScale: 2,
    );

    final scroller = find.descendant(
      of: _card,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scroller, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(scroller).scrollDirection,
      Axis.horizontal,
    );

    final rects = _dayRects(tester);
    final content = _contentRect(tester);
    expect(rects.first.width, greaterThan(60));
    for (var i = 0; i < 7; i++) {
      expect(rects[i].width, closeTo(rects.first.width, 0.5));
    }
    // 大字下七格必然超出可用宽度，因此内容比视口宽。
    expect(rects.last.right, greaterThan(content.right));
    expectPercentComplete(tester, rects);

    await tester.drag(scroller, const Offset(-500, 0));
    await tester.pumpAndSettle();
    final scrolled = _dayRects(tester);
    expect(
      scrolled.last.right,
      lessThanOrEqualTo(content.right + 1),
      reason: '横向滚动后可看到最后一格',
    );
    expectPercentComplete(tester, scrolled);
    expect(tester.takeException(), isNull);
  });
}
