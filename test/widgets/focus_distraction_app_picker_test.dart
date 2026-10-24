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
}
