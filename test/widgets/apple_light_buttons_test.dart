import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/apple_button_style.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = AppBrands.defaultBrand.theme;
  final idleStates = <Set<WidgetState>>[
    {},
    {WidgetState.hovered},
    {WidgetState.pressed},
    {WidgetState.selected},
    {WidgetState.disabled},
    {WidgetState.disabled, WidgetState.focused},
  ];

  test('Apple outlined and segmented actions have no resting dark edge', () {
    for (final style in [
      theme.outlinedButtonTheme.style!,
      theme.segmentedButtonTheme.style!,
    ]) {
      for (final states in idleStates) {
        expect(style.side!.resolve(states)!.style, BorderStyle.none);
      }
      final focus = style.side!.resolve({WidgetState.focused})!;
      expect(focus.style, BorderStyle.solid);
      expect(focus.color, theme.colorScheme.primary.withValues(alpha: 0.42));
      expect(focus.width, lessThanOrEqualTo(1));
      expect(
        style.overlayColor!.resolve({WidgetState.hovered})!.a,
        greaterThan(0),
      );
      expect(
        style.overlayColor!.resolve({WidgetState.pressed})!.a,
        greaterThan(0),
      );
    }
    expect(
      theme.outlinedButtonTheme.style!.backgroundColor!.resolve({
        WidgetState.disabled,
      }),
      Colors.transparent,
    );
  });

  test('Apple text, primary and icon variants have no hard outline', () {
    for (final style in [
      theme.textButtonTheme.style!,
      theme.filledButtonTheme.style!,
      theme.elevatedButtonTheme.style!,
      theme.iconButtonTheme.style!,
    ]) {
      for (final states in idleStates) {
        expect(style.side!.resolve(states)!.style, BorderStyle.none);
      }
    }
    expect(
      theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
      isNot(theme.outlinedButtonTheme.style!.backgroundColor!.resolve({})),
      reason: 'Primary actions retain their stronger semantic fill',
    );
  });

  test(
    'Apple chips resolve to a light resting state and a coloured keyboard focus',
    () {
      for (final states in idleStates) {
        final side = WidgetStateProperty.resolveAs<BorderSide?>(
          theme.chipTheme.side,
          states,
        )!;
        expect(side.style, BorderStyle.none);
      }
      final focus = WidgetStateProperty.resolveAs<BorderSide?>(
        theme.chipTheme.side,
        {WidgetState.focused},
      )!;
      expect(focus.color, theme.colorScheme.primary.withValues(alpha: 0.42));
      expect(
        theme.chipTheme.selectedColor,
        isNot(theme.chipTheme.backgroundColor),
      );
    },
  );

  test('Other brands retain their outlined button definitions', () {
    for (final brand in AppBrands.all.where(
      (brand) => brand.style != BrandStyle.defaultBrand,
    )) {
      final other = brand.theme;
      expect(AppleButtonStyle.appliesTo(other), isFalse, reason: brand.id);
      expect(AppleButtonStyle.outlined(other).side, isNull, reason: brand.id);
      expect(AppleButtonStyle.borderless(other).side, isNull, reason: brand.id);
      final side = other.outlinedButtonTheme.style!.side!.resolve({})!;
      expect(side.style, BorderStyle.solid, reason: brand.id);
      expect(side.width, closeTo(0.7, 0.001), reason: brand.id);
    }
  });

  for (final secondary in [false, true]) {
    testWidgets(
      '${secondary ? 'Secondary surfaces' : 'Root pages'} render outlined controls without black edges',
      (tester) async {
        Widget controls = Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('outlined'),
              onPressed: () {},
              child: const Text('Action'),
            ),
            OutlinedButton(
              key: const ValueKey('disabled'),
              onPressed: null,
              child: const Text('Disabled'),
            ),
            IconButton.outlined(
              key: const ValueKey('icon'),
              onPressed: () {},
              icon: const Icon(Icons.edit),
            ),
            ChoiceChip(
              key: const ValueKey('choice'),
              label: const Text('Choice'),
              selected: false,
              onSelected: (_) {},
            ),
            FilterChip(
              key: const ValueKey('filter'),
              label: const Text('Selected'),
              selected: true,
              onSelected: (_) {},
            ),
            ActionChip(
              key: const ValueKey('action'),
              label: const Text('Chip'),
              onPressed: () {},
            ),
            InputChip(
              key: const ValueKey('input'),
              label: const Text('Tag'),
              onDeleted: () {},
            ),
          ],
        );
        if (secondary) controls = AppSecondaryControlTheme(child: controls);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: controls),
          ),
        );
        await tester.pumpAndSettle();
        if (secondary) {
          final nestedTheme = Theme.of(
            tester.element(find.byKey(const ValueKey('outlined'))),
          );
          final segment = nestedTheme.segmentedButtonTheme.style!;
          expect(segment.backgroundColor!.resolve({}), Colors.transparent);
          expect(
            segment.backgroundColor!.resolve({WidgetState.selected}),
            Color.alphaBlend(
              nestedTheme.colorScheme.primary.withValues(alpha: 0.09),
              nestedTheme.colorScheme.surface,
            ),
          );
        }
        for (final id in [
          'outlined',
          'disabled',
          'icon',
          'choice',
          'filter',
          'action',
          'input',
        ]) {
          final material = tester.widget<Material>(
            find
                .descendant(
                  of: find.byKey(ValueKey(id)),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(
            (material.shape! as OutlinedBorder).side.style,
            BorderStyle.none,
            reason: id,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Local danger foreground survives the light style and focus remains visible',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: OutlinedButton(
              focusNode: focus,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ).merge(AppleButtonStyle.outlined(theme)),
              onPressed: () {},
              child: const Text('Delete'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(
        button.style!.foregroundColor!.resolve({}),
        theme.colorScheme.error,
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(OutlinedButton),
              matching: find.byType(Material),
            )
            .first,
      );
      final side = (material.shape! as OutlinedBorder).side;
      expect(side.style, BorderStyle.solid);
      expect(side.color, theme.colorScheme.primary.withValues(alpha: 0.42));
      expect(tester.takeException(), isNull);
    },
  );
}
