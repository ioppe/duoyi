import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('底部导航操作区在窄屏和 $scale 倍字号下不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => PreferencesProvider(),
          child: MaterialApp(
            theme: AppBrands.defaultBrand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const BottomNavSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final actions = find.byKey(const ValueKey('bottom_nav_actions_0'));
      expect(actions, findsOneWidget);
      expect(tester.getSize(actions).width, kMinInteractiveDimension * 2 + 56);
      expect(tester.takeException(), isNull);
    });

    testWidgets('设置操作按钮等高并支持 $scale 倍字号', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: AppSecondaryControlTheme(
              child: SingleChildScrollView(
                child: Wrap(
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('保存')),
                    ElevatedButton(onPressed: () {}, child: const Text('保存')),
                    OutlinedButton(onPressed: () {}, child: const Text('保存')),
                    TextButton(onPressed: () {}, child: const Text('保存')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heights = [
        for (final type in [
          FilledButton,
          ElevatedButton,
          OutlinedButton,
          TextButton,
        ])
          tester.getSize(find.byType(type)).height,
      ];
      for (final height in heights) {
        expect(height, greaterThanOrEqualTo(DesignTokens.controlMinHeight));
        expect(height, closeTo(heights.first, 0.01));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏设置控件保留真实尺寸并支持 $scale 倍字号', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const actionKey = ValueKey('settings-action');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: AppSecondaryControlTheme(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: AppSettingsTile(
                  icon: Icons.public,
                  title: '应用时区与日期显示',
                  subtitle: '设置在退出并重新启动应用后仍然保留。',
                  color: Colors.blue,
                  trailing: AppCompactDropdown<String>(
                    key: actionKey,
                    width: 156,
                    value: 'Asia/Shanghai',
                    items: const [
                      DropdownMenuItem(
                        value: 'Asia/Shanghai',
                        child: Text('上海 / 北京'),
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = tester.getRect(find.byKey(actionKey));
      final title = tester.getRect(find.text('应用时区与日期显示'));
      expect(action.width, 156);
      expect(
        action.height,
        greaterThanOrEqualTo(DesignTokens.controlMinHeight),
      );
      expect(action.top, greaterThan(title.bottom));
      expect(action.right, lessThanOrEqualTo(320));
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
