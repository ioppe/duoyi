import 'package:duoyi/services/focus_distraction_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a persisted native block cannot be replayed into a new focus session',
    () {
      const old = FocusNativeBlockEvent(
        packageName: 'com.example.app',
        blockedAtMs: 900,
      );
      expect(
        old.shouldRecord(
          lastConsumedBlockedAtMs: 0,
          lastRecordedPackage: null,
          blockedPackages: const ['com.example.app'],
          notBeforeMs: 1000,
        ),
        isFalse,
      );
      const current = FocusNativeBlockEvent(
        packageName: 'com.example.app',
        blockedAtMs: 1500,
      );
      expect(
        current.shouldRecord(
          lastConsumedBlockedAtMs: 0,
          lastRecordedPackage: null,
          blockedPackages: const ['com.example.app'],
          notBeforeMs: 1000,
        ),
        isTrue,
      );
      expect(
        current.shouldRecord(
          lastConsumedBlockedAtMs: 1500,
          lastRecordedPackage: null,
          blockedPackages: const ['com.example.app'],
          notBeforeMs: 1000,
        ),
        isFalse,
      );
    },
  );
}
