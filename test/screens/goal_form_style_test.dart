import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/todo_create_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _openHarness(
  WidgetTester tester, {
  required ThemeData theme,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
        ChangeNotifierProvider(create: (_) => TodoProvider()),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AiService()),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showGoalCreateSheet(context),
                  child: const Text('open-goal'),
                ),
                TextButton(
                  onPressed: () => showTodoCreateSheet(context),
                  child: const Text('open-todo'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TextStyle _inputStyle(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .style;

InputDecorationThemeData _decoration(WidgetTester tester, Finder field) =>
    Theme.of(tester.element(field)).inputDecorationTheme;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(DesignTokens.fontFamily)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brand in [AppBrands.defaultBrand, AppBrands.starRail]) {
    for (final (size, scale) in [
      (const Size(1600, 1000), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(320, 720), 1.5),
    ]) {
      testWidgets('${brand.id} $size ×$scale 新建目标与新建任务共用表单尺寸和字体', (
        tester,
      ) async {
        await _openHarness(
          tester,
          theme: brand.theme,
          size: size,
          textScale: scale,
        );
        await tester.tap(find.text('open-todo'));
        await tester.pumpAndSettle();
        final task = _key('todo_create_title');
        final taskStyle = _inputStyle(tester, task);
        final taskDecoration = _decoration(tester, task);
        final sheet = tester.widget<AppModalSheet>(_key('todo_create_sheet'));
        expect(sheet.maxWidth, DesignTokens.creationFormMaxWidth);
        expect(
          tester.getSize(task).height,
          greaterThanOrEqualTo(DesignTokens.formFieldMinHeight),
        );
        await tester.ensureVisible(_key('todo_create_submit'));
        await tester.pumpAndSettle();
        final taskButtonHeight = tester
            .getSize(_key('todo_create_submit'))
            .height;
        Navigator.of(tester.element(task)).pop();
        await tester.pumpAndSettle();

        await tester.tap(find.text('open-goal'));
        await tester.pumpAndSettle();
        final title = _key('goal_form_title');
        final description = _key('goal_form_description');
        final goalStyle = _inputStyle(tester, title);
        final goalDecoration = _decoration(tester, title);
        expect(goalStyle.fontFamily, taskStyle.fontFamily);
        expect(goalStyle.fontWeight, taskStyle.fontWeight);
        expect(goalStyle.fontSize, taskStyle.fontSize);
        expect(goalStyle.height, taskStyle.height);
        expect(goalStyle.fontSize, DesignTokens.fontSizeMd);
        expect(goalDecoration.contentPadding, taskDecoration.contentPadding);
        expect(goalDecoration.constraints, taskDecoration.constraints);
        expect(goalDecoration.enabledBorder, taskDecoration.enabledBorder);
        expect(goalDecoration.focusedBorder, taskDecoration.focusedBorder);
        expect(goalDecoration.labelStyle, taskDecoration.labelStyle);
        expect(_inputStyle(tester, description).fontSize, taskStyle.fontSize);
        expect(
          tester.getSize(title).height,
          greaterThanOrEqualTo(DesignTokens.formFieldMinHeight),
        );
        expect(
          tester.getSize(description).height,
          greaterThan(tester.getSize(title).height),
        );
        final form = tester.getRect(_key('goal_form_content'));
        expect(
          form.width,
          lessThanOrEqualTo(DesignTokens.creationFormMaxWidth),
        );
        expect(form.center.dx, closeTo(size.width / 2, 0.01));
        expect(
          tester.getSize(_key('goal_start_date_field')).height,
          greaterThanOrEqualTo(DesignTokens.formFieldMinHeight),
        );
        expect(
          tester.getSize(_key('goal_target_date_field')).height,
          greaterThanOrEqualTo(DesignTokens.formFieldMinHeight),
        );
        await tester.scrollUntilVisible(
          _key('goal_form_submit'),
          320,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester.getSize(_key('goal_form_submit')).height,
          taskButtonHeight,
        );
        await tester.tap(_key('goal_form_cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(GoalEditScreen), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('新建目标底部保存按钮提交名称和描述并返回', (tester) async {
    await _openHarness(tester, theme: AppBrands.defaultBrand.theme);
    final provider = tester
        .element(find.text('open-goal'))
        .read<GoalProvider>();
    await tester.tap(find.text('open-goal'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('goal_form_title'), '年度阅读');
    await tester.enterText(_key('goal_form_description'), '读完24本书\n每月复盘一次');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      _key('goal_form_submit'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(_key('goal_form_submit'));
    await tester.pumpAndSettle();
    expect(provider.goals, hasLength(1));
    expect(provider.goals.single.title, '年度阅读');
    expect(provider.goals.single.description, '读完24本书\n每月复盘一次');
    expect(find.byType(GoalEditScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
