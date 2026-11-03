import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 系统小组件列表中的 4 个标准入口（与原生 catalog 一致）。
const List<String> _coreCatalogTitles = <String>['今日待办', '专注', '习惯', '月历'];

/// 仅保留给已添加旧实例的 5 个次级品类。
const List<String> _secondaryCatalogTitles = <String>[
  '今日日程',
  '目标',
  '课程表',
  '随手记',
  '纪念日',
];

/// ListTile 只被目录条目使用，可据此精确统计目录数量，
/// 避免与小组件预览卡片里的「待办 / 习惯 / 专注」文案混淆。
Finder _catalogTiles() => find.byType(ListTile);

Future<void> _pumpWidgetCatalog(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.binding.setSurfaceSize(const Size(420, 7000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: WidgetScreen()));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    AndroidWidgetManager.debugNativeAndroid = null;
  });

  group('Android 小组件目录收敛到核心 4 类', () {
    test('生产目录常量等于 4 个标准品类，历史 9 类序列化保持不变', () {
      expect(AndroidWidgetManager.catalogKinds, const <DuoyiWidgetKind>[
        DuoyiWidgetKind.todo,
        DuoyiWidgetKind.focus,
        DuoyiWidgetKind.habit,
        DuoyiWidgetKind.calendar,
      ]);
      expect(DuoyiWidgetKind.values.length, 9);
      expect(
        DuoyiWidgetKind.values
            .where((kind) => !AndroidWidgetManager.catalogKinds.contains(kind))
            .toList(),
        const <DuoyiWidgetKind>[
          DuoyiWidgetKind.schedule,
          DuoyiWidgetKind.goal,
          DuoyiWidgetKind.course,
          DuoyiWidgetKind.note,
          DuoyiWidgetKind.anniversary,
        ],
      );
    });

    testWidgets('Android 只渲染 4 个标准入口，次级品类不进入目录', (tester) async {
      AndroidWidgetManager.debugNativeAndroid = true;
      await _pumpWidgetCatalog(tester);

      expect(_catalogTiles(), findsNWidgets(_coreCatalogTitles.length));
      for (final title in _coreCatalogTitles) {
        expect(
          find.widgetWithText(ListTile, title),
          findsOneWidget,
          reason: title,
        );
      }
      for (final title in _secondaryCatalogTitles) {
        expect(
          find.widgetWithText(ListTile, title),
          findsNothing,
          reason: title,
        );
      }
      // 密度面板仍是显示偏好，不作为重复的目录条目。
      expect(find.byType(SegmentedButton<WidgetDisplayMode>), findsOneWidget);
      expect(
        find.text(I18n.tr('widget.android_catalog_density_hint')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('非 Android 平台保留 9 个预览目录与原有引导', (tester) async {
      await _pumpWidgetCatalog(tester);

      expect(_catalogTiles(), findsNWidgets(9));
      for (final title in <String>[
        ..._coreCatalogTitles,
        ..._secondaryCatalogTitles,
      ]) {
        expect(
          find.widgetWithText(ListTile, title),
          findsOneWidget,
          reason: title,
        );
      }
      expect(
        find.text(I18n.tr('widget.android_catalog_density_hint')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
