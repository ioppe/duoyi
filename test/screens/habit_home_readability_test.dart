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
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';

/// 固定应用墙钟：2026-03-11 周三，今日打卡语义可预测。
final DateTime _fixedNow = DateTime(2026, 3, 11, 9, 15);

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

Finder _card(String id) => find.byKey(ValueKey('habit_checkin_card_$id'));
Finder _title(String id) => find.byKey(ValueKey('habit_checkin_title_$id'));

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

  Future<HabitProvider> readableProvider() async {
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(
        id: 'brush',
        name: '睡前刷牙',
        icon: Icons.brush.codePoint.toString(),
        startDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await provider.addHabit(
      Habit(
        id: 'long',
        name: '每日复盘并记录三件值得感恩的小事与明日计划',
        icon: Icons.edit_note.codePoint.toString(),
        unit: '分钟',
        targetCount: 3,
        startDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await provider.addHabit(
      Habit(
        id: 'neg',
        name: '少喝咖啡',
        icon: Icons.local_cafe_outlined.codePoint.toString(),
        kind: HabitKind.negative,
        unit: '杯',
        startDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        completions: {_dateKey(_fixedNow): 1},
      ),
    );
    await provider.addHabit(
      Habit(
        id: 'flex',
        name: '每周三次力量训练',
        icon: Icons.fitness_center.codePoint.toString(),
        flexPeriod: HabitFlexPeriod.week,
        flexTarget: 3,
        startDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    return provider;
  }

  Future<void> openHabit(
    WidgetTester tester, {
    required HabitProvider provider,
    required Size size,
    required ThemeData theme,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const HabitScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder item) async {
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('habit_today_scroll_view')),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    if (item.evaluate().isEmpty) {
      await tester.scrollUntilVisible(item, 180, scrollable: scrollable);
    } else {
      await tester.ensureVisible(item);
    }
    await tester.pumpAndSettle();
  }

  Rect paintedCard(WidgetTester tester, String id) => tester.getRect(
    find.descendant(of: _card(id), matching: find.byType(Ink)).first,
  );

  /// 卡内正文标题必须完整：没有被 ellipsis 截断、行数正确、落在卡体内。
  void expectTitleReadable(WidgetTester tester, String id, {int maxLines = 1}) {
    final titleFinder = _title(id);
    expect(titleFinder, findsOneWidget, reason: '缺少 $id 的标题');
    final cardRect = paintedCard(tester, id);
    final titleRect = tester.getRect(titleFinder);
    final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '$id 的标题被截断（用户报告的「睡前刷牙只露出一半」）',
    );
    final singleLineHeight = paragraph.getMaxIntrinsicHeight(double.infinity);
    expect(
      paragraph.size.height,
      lessThanOrEqualTo(singleLineHeight * maxLines + 0.5),
      reason: '$id 的标题行数超出预期',
    );
    expect(titleRect.top, greaterThanOrEqualTo(cardRect.top - 0.5));
    expect(titleRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));
    expect(titleRect.left, greaterThanOrEqualTo(cardRect.left - 0.5));
    expect(titleRect.right, lessThanOrEqualTo(cardRect.right + 0.5));
    expect(titleRect.height, greaterThan(16));

    // 辅助信息不能与标题重叠。
    final meta = find.descendant(
      of: _card(id),
      matching: find.textContaining('目标:'),
    );
    expect(meta, findsOneWidget);
    expect(
      tester.getRect(meta).top,
      greaterThanOrEqualTo(titleRect.bottom - 0.5),
      reason: '$id 的辅助信息压在标题上',
    );
  }

  void expectActionTargets(WidgetTester tester, String id) {
    final button = find.descendant(
      of: _card(id),
      matching: find.byType(FilledButton),
    );
    final undo = find.descendant(
      of: _card(id),
      matching: find.byKey(const ValueKey('habit-undo-inline-button')),
    );
    expect(button, findsOneWidget);
    expect(undo, findsOneWidget);
    expect(
      tester.getRect(button).height,
      greaterThanOrEqualTo(DesignTokens.controlMinHeight - 0.5),
      reason: '打卡按钮触控高度不足 44',
    );
    expect(
      tester.getRect(undo).height,
      greaterThanOrEqualTo(DesignTokens.controlMinHeight - 0.5),
      reason: '撤回按钮触控高度不足 44',
    );
  }

  for (final theme in [
    AppBrands.defaultBrand.theme,
    AppBrands.starRail.theme,
  ]) {
    for (final (size, scale) in [
      (const Size(369.23, 821.5), 1.25),
      (const Size(390, 844), 1.0),
      (const Size(320, 720), 1.5),
      (const Size(320, 720), 2.0),
      (const Size(390, 844), 2.0),
    ]) {
      testWidgets('${theme.brightness} $size ×$scale 习惯卡标题完整且信息不重叠', (
        tester,
      ) async {
        final provider = await readableProvider();
        await openHabit(
          tester,
          provider: provider,
          size: size,
          theme: theme,
          textScale: scale,
        );

        await reveal(tester, _title('brush'));
        expectTitleReadable(tester, 'brush');
        expectActionTargets(tester, 'brush');

        final cardRect = paintedCard(tester, 'brush');
        expect(
          cardRect.height,
          greaterThan(80),
          reason: '卡体是自然高度（含 16 正文 + 辅助 14 + 进度线）',
        );
        expect(cardRect.width, closeTo(size.width - 24, 0.5));

        // 窄屏（<=360）或 1.5x 以上大字号：动作按钮挪到下方右对齐。
        final innerWidth = size.width - 52;
        final stacked = innerWidth <= 300 || scale >= 1.5 - 0.01;
        final button = find.descendant(
          of: _card('brush'),
          matching: find.byType(FilledButton),
        );
        final titleRect = tester.getRect(_title('brush'));
        final buttonRect = tester.getRect(button);
        if (stacked) {
          expect(
            buttonRect.top,
            greaterThanOrEqualTo(titleRect.bottom),
            reason: '窄屏/大字时动作按钮应在标题下方',
          );
          expect(
            buttonRect.right,
            greaterThan(tester.getRect(_card('brush')).center.dx),
            reason: '下方动作按钮右对齐',
          );
        } else {
          expect(
            buttonRect.left,
            greaterThanOrEqualTo(tester.getRect(_title('brush')).right - 0.5),
            reason: '宽屏时动作按钮在标题右侧，标题不被挤成窄列',
          );
        }

        // 长标题最多两行，卡体自然增高且内容不被裁掉。
        await reveal(tester, _title('long'));
        final longCard = paintedCard(tester, 'long');
        expect(longCard.height, greaterThan(80));
        final longTitle = tester.renderObject<RenderParagraph>(_title('long'));
        expect(
          longTitle.size.height,
          lessThanOrEqualTo(
            longTitle.getMaxIntrinsicHeight(double.infinity) * 2 + 0.5,
          ),
        );
        final longTitleRect = tester.getRect(_title('long'));
        expect(longTitleRect.top, greaterThanOrEqualTo(longCard.top - 0.5));
        expect(longTitleRect.bottom, lessThanOrEqualTo(longCard.bottom + 0.5));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('369dp 1.25 字号「睡前刷牙」单行完整显示', (tester) async {
    final provider = await readableProvider();
    await openHabit(
      tester,
      provider: provider,
      size: const Size(369.23, 821.5),
      theme: AppBrands.defaultBrand.theme,
      textScale: 1.25,
    );
    final button = find.descendant(
      of: _card('brush'),
      matching: find.byType(FilledButton),
    );
    expect(button.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(button).bottom,
      lessThan(tester.getRect(find.byType(FloatingActionButton)).top),
      reason: '小米等效首屏上，第一条打卡操作不能被添加习惯悬浮按钮遮住。',
    );
    await reveal(tester, _title('brush'));
    expectTitleReadable(tester, 'brush', maxLines: 1);
    expect(
      tester.widget<Text>(_title('brush')).data,
      '睡前刷牙',
      reason: '标题文本必须完整，不允许被截短',
    );
  });

  testWidgets('打卡与撤回在窄屏 2 倍字号下可用', (tester) async {
    final provider = await readableProvider();
    await openHabit(
      tester,
      provider: provider,
      size: const Size(320, 720),
      theme: AppBrands.defaultBrand.theme,
      textScale: 2,
    );

    await reveal(tester, _card('brush'));
    final checkIn = find.descendant(
      of: _card('brush'),
      matching: find.text('打卡'),
    );
    expect(checkIn, findsOneWidget);
    await reveal(tester, checkIn);
    await tester.tap(checkIn);
    await tester.pumpAndSettle();
    expect(provider.habits.first.todayCount(), 1);
    final completedButton = find.descendant(
      of: _card('brush'),
      matching: find.byType(FilledButton),
    );
    await reveal(tester, completedButton);
    expect(tester.widget<FilledButton>(completedButton).onPressed, isNull);
    await tester.tapAt(tester.getCenter(completedButton));
    await tester.pumpAndSettle();
    expect(find.byType(HabitDetailScreen), findsNothing);
    expect(provider.habits.first.todayCount(), 1);
    final undo = find.descendant(
      of: _card('brush'),
      matching: find.byKey(const ValueKey('habit-undo-inline-button')),
    );
    await reveal(tester, undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(provider.habits.first.todayCount(), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧滑编辑/结束/删除与详情导航在自然高度卡片上仍可用', (tester) async {
    final provider = await readableProvider();
    await openHabit(
      tester,
      provider: provider,
      size: const Size(369.23, 821.5),
      theme: AppBrands.defaultBrand.theme,
      textScale: 1.25,
    );

    await reveal(tester, _title('brush'));
    final originalTitleCenter = tester.getCenter(_title('brush'));
    await tester.drag(_title('brush'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('habit_swipe_edit_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('habit_swipe_end_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('habit_swipe_delete_button')),
      findsOneWidget,
    );

    await tester.dragFrom(originalTitleCenter, const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habit_swipe_edit_button')), findsNothing);
    await reveal(tester, _title('brush'));
    await tester.tap(_title('brush'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1280 宽屏今日打卡两列自然高度、不裁卡片', (tester) async {
    final provider = await readableProvider();
    await openHabit(
      tester,
      provider: provider,
      size: const Size(1280, 900),
      theme: AppBrands.defaultBrand.theme,
    );

    final brush = tester.getRect(_card('brush'));
    final long = tester.getRect(_card('long'));
    final neg = tester.getRect(_card('neg'));

    // 同一行两列：顶部与宽度一致，各自自然高度。
    expect(brush.top, closeTo(long.top, 0.5));
    expect(brush.width, closeTo(long.width, 0.5));
    expect(brush.width, greaterThan(300));
    // 第二行开始于第一行结束之后（不是固定高度裁切）。
    expect(neg.top, greaterThanOrEqualTo(brush.top + brush.height - 1));
    // 两列卡体高度按内容自然增高，而不是旧的固定 extent。
    expect(brush.height, greaterThan(80));
    expect(long.height, greaterThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('400 高初始一屏仍显示概览，习惯卡需要滚动才能看到', (tester) async {
    final provider = await readableProvider();
    await openHabit(
      tester,
      provider: provider,
      size: const Size(390, 400),
      theme: AppBrands.defaultBrand.theme,
    );

    expect(
      find.byKey(const ValueKey('habit_weekly_overview_card')),
      findsOneWidget,
    );
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('habit_today_scroll_view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
