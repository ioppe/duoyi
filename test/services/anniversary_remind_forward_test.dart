import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/services/reminder_scheduler.dart';

void main() {
  group('rollAnniversaryRemindAtForward（周年漏提醒修复）', () {
    test('未来时刻原样返回', () {
      final now = DateTime(2026, 6, 1, 10, 0);
      final remindAt = DateTime(2026, 6, 1, 18, 0);
      expect(rollAnniversaryRemindAtForward(remindAt, now), remindAt);
    });

    test('提醒时刻已过当天当前时间：推进到下一年同一时刻', () {
      final now = DateTime(2026, 6, 1, 10, 0);
      // 周年是今天，但提醒时刻 08:00 已过 → 不再跳过，注册到明年。
      final remindAt = DateTime(2026, 6, 1, 8, 0);
      expect(
        rollAnniversaryRemindAtForward(remindAt, now),
        DateTime(2027, 6, 1, 8, 0),
      );
    });

    test('提醒时刻恰等于当前时间：视为已过并推进（安全侧）', () {
      final now = DateTime(2026, 6, 1, 10, 0);
      final remindAt = DateTime(2026, 6, 1, 10, 0);
      expect(
        rollAnniversaryRemindAtForward(remindAt, now),
        DateTime(2027, 6, 1, 10, 0),
      );
    });

    test('闰日 2/29 推进后自动滚动到 3/1', () {
      final now = DateTime(2026, 3, 1, 12, 0);
      // 2024-02-29 是已过的闰日提醒时刻；+1 年落到 2025（非闰年），
      // DateTime 构造自动滚动到 2025-03-01。
      final remindAt = DateTime(2024, 2, 29, 9, 0);
      expect(
        rollAnniversaryRemindAtForward(remindAt, now),
        DateTime(2025, 3, 1, 9, 0),
      );
    });
  });

  group('scheduler 接入锚点', () {
    test('syncAnniversaries 已过时刻改为推进而非跳过', () {
      final source = File(
        'lib/services/reminder_scheduler.dart',
      ).readAsStringSync();

      expect(source, contains('rollAnniversaryRemindAtForward('));
      expect(
        source,
        contains(
          'final remindAt = rollAnniversaryRemindAtForward(',
        ),
      );
      // 兜底跳过仍保留（remindDaysBefore 极大等极端场景）。
      expect(source, contains('if (!remindAt.isAfter(AppClock.now()))'));
    });
  });
}
