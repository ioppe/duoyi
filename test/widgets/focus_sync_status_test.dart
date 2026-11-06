import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/widgets/focus_sync_status.dart';
import 'package:duoyi/widgets/pomodoro_timer_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FocusProvider extends PomodoroProvider {
  bool enabled = true;
  bool ready = true;
  bool connected = false;
  Object? error;

  @override
  bool get focusSyncEnabled => enabled;
  @override
  bool get focusSyncReady => ready;
  @override
  bool get focusSyncConnected => connected;
  @override
  Object? get focusSyncError => error;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scenario
      in <
        ({
          String name,
          bool loggedIn,
          bool enabled,
          bool ready,
          bool connected,
          bool failed,
          String messageKey,
          IconData icon,
        })
      >[
        (
          name: 'guest always sees a cloud with the login hint',
          loggedIn: false,
          enabled: false,
          ready: false,
          connected: false,
          failed: false,
          messageKey: 'focus.sync.login_required',
          icon: Icons.cloud_off_outlined,
        ),
        (
          name: 'signed-in disconnected focus shows the offline hint',
          loggedIn: true,
          enabled: true,
          ready: true,
          connected: false,
          failed: false,
          messageKey: 'focus.sync.offline',
          icon: Icons.cloud_off_outlined,
        ),
        (
          name: 'connection without an authoritative snapshot is unsynced',
          loggedIn: true,
          enabled: true,
          ready: false,
          connected: true,
          failed: false,
          messageKey: 'focus.sync.offline',
          icon: Icons.cloud_off_outlined,
        ),
        (
          name: 'an unconfirmed error is unsynced even with a live connection',
          loggedIn: true,
          enabled: true,
          ready: true,
          connected: true,
          failed: true,
          messageKey: 'focus.sync.offline',
          icon: Icons.cloud_off_outlined,
        ),
        (
          name: 'signed-in local compatibility mode is unsynced',
          loggedIn: true,
          enabled: false,
          ready: true,
          connected: true,
          failed: false,
          messageKey: 'focus.sync.offline',
          icon: Icons.cloud_off_outlined,
        ),
        (
          name: 'confirmed connected focus shows the synced cloud and hint',
          loggedIn: true,
          enabled: true,
          ready: true,
          connected: true,
          failed: false,
          messageKey: 'focus.sync.connected',
          icon: Icons.cloud_done_outlined,
        ),
        (
          name: 'guest hint takes precedence over stale connected flags',
          loggedIn: false,
          enabled: true,
          ready: true,
          connected: true,
          failed: false,
          messageKey: 'focus.sync.login_required',
          icon: Icons.cloud_off_outlined,
        ),
      ]) {
    testWidgets(scenario.name, (tester) async {
      final provider = _FocusProvider()
        ..enabled = scenario.enabled
        ..ready = scenario.ready
        ..connected = scenario.connected
        ..error = scenario.failed ? const FormatException('offline') : null;
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FocusSyncStatus(
              provider: provider,
              isLoggedIn: scenario.loggedIn,
            ),
          ),
        ),
      );

      final message = I18n.tr(scenario.messageKey);
      expect(find.byIcon(scenario.icon), findsOneWidget);
      expect(find.byIcon(Icons.cloud), findsOneWidget);
      expect(find.byTooltip(message), findsOneWidget);
      expect(find.text(message), findsNothing);
      final button = find.byType(IconButton);
      expect(
        tester.getSize(button).shortestSide,
        greaterThanOrEqualTo(DesignTokens.controlMinHeight),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cloud hint fits a narrow dark screen with large text', (
    tester,
  ) async {
    final provider = _FocusProvider()..enabled = false;
    addTearDown(provider.dispose);
    await tester.binding.setSurfaceSize(const Size(240, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Row(
            children: [
              const Flexible(child: Text('专注中')),
              FocusSyncStatus(provider: provider, isLoggedIn: false),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('focus.sync.login_required')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'cloud preserves compact title/count spacing at ${textScale}x',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const PomodoroScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final cloud = find.byType(FocusSyncStatus);
        final title = find.text('专注中');
        final count = find.text('0 次专注');
        expect(cloud, findsOneWidget);
        expect(title, findsOneWidget);
        expect(count, findsOneWidget);
        final titleBounds = tester.getRect(title);
        final countBounds = tester.getRect(count);
        expect(
          countBounds.top - titleBounds.bottom,
          inInclusiveRange(0, DesignTokens.spaceXxs + 0.01),
        );
        expect(countBounds.left, closeTo(titleBounds.left, 0.01));
        expect(tester.getCenter(cloud).dx, greaterThan(titleBounds.right));
        expect(
          tester.getCenter(cloud).dy,
          closeTo((titleBounds.top + countBounds.bottom) / 2, 1),
        );
        expect(
          tester.getBottomLeft(cloud).dy,
          lessThan(tester.getTopLeft(find.byType(PomodoroTimerRing)).dy),
        );
        expect(find.text(I18n.tr('focus.sync.connected')), findsNothing);
        expect(find.text(I18n.tr('focus.sync.offline')), findsNothing);
        expect(find.text(I18n.tr('focus.sync.login_required')), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('focus_sync_status_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text(I18n.tr('focus.sync.login_required')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
