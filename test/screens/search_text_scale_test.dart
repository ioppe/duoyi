import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_text_scale.dart';
import 'package:duoyi/core/app_typography.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _SearchTodos extends TodoProvider {
  final _items = <TodoItem>[
    TodoItem(
      id: 'search-text-scale',
      title: '量子任务标题',
      notes: '量子任务摘要',
      date: DateTime(2026, 10, 25),
      createdAt: DateTime.utc(2026, 10, 25),
      updatedAt: DateTime.utc(2026, 10, 25),
    ),
  ];

  @override
  List<TodoItem> get todos => _items;
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) => fontSize + 8 * fontSize / (fontSize + 8);

  @override
  double get textScaleFactor => scale(1);
}

void main() {
  setUpAll(() async {
    await (FontLoader(DesignTokens.fontFamily)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
    await (FontLoader(
      Icons.search.fontFamily!,
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final system in <TextScaler>[
    TextScaler.noScaling,
    const TextScaler.linear(1.5),
    const _NonlinearScaler(),
  ]) {
    testWidgets(
      '搜索高亮标题和摘要在安卓七档继承实际文字缩放：$system',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final titleHeights = <double, double>{};
        for (final ratio in AppTextScale.androidOptions) {
          final scaler = AppTextScale.resolve(
            system: AppTypography.platformScaler(
              system: system,
              platform: TargetPlatform.android,
              isWeb: false,
            ),
            appScale: ratio,
            platform: TargetPlatform.android,
            isWeb: false,
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<TodoProvider>(
                  create: (_) => _SearchTodos(),
                ),
                ChangeNotifierProvider(create: (_) => HabitProvider()),
                ChangeNotifierProvider(create: (_) => NoteProvider()),
                ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
                ChangeNotifierProvider(create: (_) => CountdownProvider()),
                ChangeNotifierProvider(create: (_) => GoalProvider()),
                ChangeNotifierProvider(create: (_) => CourseProvider()),
                ChangeNotifierProvider(create: (_) => CalendarProvider()),
                ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
              ],
              child: MaterialApp(
                theme: AppBrands.defaultBrand.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: scaler),
                  child: child!,
                ),
                home: const SearchScreen(),
              ),
            ),
          );
          await tester.enterText(find.byType(TextField), '量子');
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          for (final text in ['量子任务标题', '量子任务摘要']) {
            final result = find.byWidgetPredicate(
              (widget) =>
                  widget is RichText && widget.text.toPlainText() == text,
            );
            expect(result, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(result);
            for (final size in <double>[11, 12, 14, 18, 24]) {
              expect(
                paragraph.textScaler.scale(size),
                closeTo(system.scale(size * ratio * 12 / 14), 1e-9),
                reason: '$text / $ratio / $size',
              );
            }
            if (text == '量子任务标题') {
              titleHeights[ratio] = paragraph.size.height;
            }
          }
          expect(tester.takeException(), isNull);
        }
        expect(titleHeights[.55]!, lessThan(titleHeights[1]!));
        expect(titleHeights[1]!, lessThan(titleHeights[1.45]!));
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
