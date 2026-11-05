import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/services/focus_distraction_service.dart';
import 'package:duoyi/widgets/focus_distraction_app_picker.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _apps = <InstalledFocusApp>[
  InstalledFocusApp(label: '微信', packageName: 'com.tencent.mm'),
  InstalledFocusApp(
    label: '设置',
    packageName: 'com.android.settings',
    isSystemApp: true,
  ),
  InstalledFocusApp(label: '抖音', packageName: 'com.ss.android.ugc.aweme'),
];

Future<void> _open(
  WidgetTester tester, {
  required Future<List<InstalledFocusApp>> Function() loadApps,
  required Future<void> Function(String mode, List<String> packages) onDone,
  String initialMode = PomodoroConfig.distractionModeBlacklist,
  List<String> initialPackages = const [],
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppBrands.defaultBrand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppModalSheet<void>(
              context: context,
              builder: (_) => FocusDistractionAppPicker(
                initialMode: initialMode,
                initialPackages: initialPackages,
                loadApps: loadApps,
                onDone: onDone,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));

  testWidgets('lists launchable apps with label and package name', (
    tester,
  ) async {
    await _open(tester, loadApps: () async => _apps, onDone: (_, _) async {});

    expect(find.text('微信'), findsOneWidget);
    expect(find.text('com.tencent.mm'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(
      find.text(
        'com.android.settings · '
        '${I18n.tr('focus.distraction.picker.system_app')}',
      ),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
  });

  testWidgets('search filters by display label and package name', (
    tester,
  ) async {
    await _open(tester, loadApps: () async => _apps, onDone: (_, _) async {});

    await tester.enterText(
      find.byKey(const ValueKey('focus_distraction_search')),
      'settings',
    );
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('微信'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('focus_distraction_search')),
      '抖音',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('focus_distraction_app_com.ss.android.ugc.aweme'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('focus_distraction_app.com.android.settings')),
      findsNothing,
    );
  });

  testWidgets('done saves the drafted mode and selected packages', (
    tester,
  ) async {
    String? savedMode;
    List<String>? savedPackages;
    await _open(
      tester,
      loadApps: () async => _apps,
      onDone: (mode, packages) async {
        savedMode = mode;
        savedPackages = packages;
      },
    );

    await tester.tap(find.text(I18n.tr('focus.distraction.mode.whitelist')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('focus_distraction_app_com.tencent.mm')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus_distraction_done')));
    await tester.pumpAndSettle();

    expect(savedMode, PomodoroConfig.distractionModeWhitelist);
    expect(savedPackages, ['com.tencent.mm']);
    expect(find.byType(FocusDistractionAppPicker), findsNothing);
  });

  testWidgets('cancel keeps drafts unsaved', (tester) async {
    var saved = false;
    await _open(
      tester,
      loadApps: () async => _apps,
      initialPackages: const ['com.tencent.mm'],
      onDone: (_, _) async => saved = true,
    );

    await tester.tap(find.byKey(const ValueKey('focus_distraction_cancel')));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    expect(find.byType(FocusDistractionAppPicker), findsNothing);
  });

  testWidgets('empty scan result shows a stable empty state', (tester) async {
    await _open(
      tester,
      loadApps: () async => const <InstalledFocusApp>[],
      onDone: (_, _) async {},
    );

    expect(
      find.text(I18n.tr('focus.distraction.picker.empty')),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('load failure can be retried', (tester) async {
    var attempts = 0;
    await _open(
      tester,
      loadApps: () async {
        attempts++;
        if (attempts == 1) throw StateError('scan failed');
        return _apps;
      },
      onDone: (_, _) async {},
    );

    expect(
      find.text(I18n.tr('focus.distraction.picker.load_failed')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('focus_distraction_retry')));
    await tester.pumpAndSettle();

    expect(find.text('微信'), findsOneWidget);
    expect(attempts, 2);
  });

  for (final scenario in [
    (size: const Size(390, 844), scale: 1.0, keyboard: 0.0),
    (size: const Size(320, 640), scale: 1.5, keyboard: 0.0),
    (size: const Size(390, 844), scale: 1.5, keyboard: 250.0),
  ]) {
    testWidgets('long app list keeps save visible at ${scenario.size}, '
        '${scenario.scale}x text and ${scenario.keyboard}px keyboard', (
      tester,
    ) async {
      List<String>? savedPackages;
      final apps = List.generate(
        40,
        (index) => InstalledFocusApp(
          label: index == 38 ? 'Chrome' : '应用 $index',
          packageName: index == 38
              ? 'com.android.chrome'
              : 'com.example.app$index',
        ),
      );
      await _open(
        tester,
        loadApps: () async => apps,
        onDone: (_, packages) async => savedPackages = packages,
        size: scenario.size,
        textScale: scenario.scale,
      );
      tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
      await tester.pumpAndSettle();

      final done = find.byKey(const ValueKey('focus_distraction_done'));
      final cancel = find.byKey(const ValueKey('focus_distraction_cancel'));
      expect(done.hitTestable(), findsOneWidget);
      expect(cancel.hitTestable(), findsOneWidget);
      final chrome = find.byKey(
        const ValueKey('focus_distraction_app_com.android.chrome'),
      );
      await tester.scrollUntilVisible(
        chrome,
        200,
        scrollable: find
            .descendant(
              of: find.byType(FocusDistractionAppPicker),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first,
        maxScrolls: 80,
      );
      await tester.pumpAndSettle();
      await tester.tap(chrome);
      await tester.pumpAndSettle();
      expect(done.hitTestable(), findsOneWidget);
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(savedPackages, ['com.android.chrome']);
      expect(find.byType(FocusDistractionAppPicker), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('done stays reachable on a narrow screen with large text', (
    tester,
  ) async {
    var saved = false;
    await _open(
      tester,
      loadApps: () async => _apps,
      onDone: (_, _) async => saved = true,
      size: const Size(320, 640),
      textScale: 2,
    );

    final done = find.byKey(const ValueKey('focus_distraction_done'));
    await tester.ensureVisible(done);
    await tester.pumpAndSettle();
    await tester.tap(done);
    await tester.pumpAndSettle();

    expect(saved, isTrue);
  });

  testWidgets('renders real installed app icons and placeholder otherwise', (
    tester,
  ) async {
    // 1x1 透明 PNG：验证“有合法字节就显示真实图标”。
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
    );
    final apps = <InstalledFocusApp>[
      InstalledFocusApp(
        label: '微信',
        packageName: 'com.tencent.mm',
        iconBytes: png,
      ),
      InstalledFocusApp(label: '抖音', packageName: 'com.ss.android.ugc.aweme'),
    ];
    await _open(tester, loadApps: () async => apps, onDone: (_, _) async {});

    expect(
      find.byKey(const ValueKey('focus_distraction_icon_com.tencent.mm')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('focus_distraction_icon_placeholder_com.tencent.mm'),
      ),
      findsNothing,
    );
    // 没有图标字节的应用必须显示占位，而不是破图/空白。
    expect(
      find.byKey(
        const ValueKey(
          'focus_distraction_icon_placeholder_com.ss.android.ugc.aweme',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('focus_distraction_icon_com.ss.android.ugc.aweme'),
      ),
      findsNothing,
    );
  });

  testWidgets('app without icon bytes keeps the list usable with placeholder', (
    tester,
  ) async {
    String? savedPackage;
    final apps = <InstalledFocusApp>[
      InstalledFocusApp(label: '占位图标', packageName: 'com.example.noicon'),
    ];
    await _open(
      tester,
      loadApps: () async => apps,
      onDone: (_, packages) async => savedPackage = packages.first,
    );

    expect(find.text('占位图标'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('focus_distraction_icon_placeholder_com.example.noicon'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('focus_distraction_app_com.example.noicon')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus_distraction_done')));
    await tester.pumpAndSettle();
    expect(savedPackage, 'com.example.noicon');
  });
}
