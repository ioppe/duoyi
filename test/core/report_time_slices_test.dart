import 'dart:convert';

import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/report_engine.dart';
import 'package:duoyi/core/report_time_slices.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
  });

  test('clips and splits copies while preserving identity and metadata', () {
    final entry = TimeEntry(
      id: 'original',
      title: 'Project work',
      startAt: AppClock.date(2026, 1, 1, 23),
      endAt: AppClock.date(2026, 1, 3, 1),
      category: TimeEntryCategory.work,
      source: TimeEntrySource.todo,
      sourceId: 'todo-1',
      dedupeKey: 'todo:todo-1:completion',
      note: 'Original note',
      createdAt: DateTime.utc(2025, 12, 30),
      updatedAt: DateTime.utc(2026, 1, 3, 9),
    );
    final before = entry.toJson();
    final entries = List<TimeEntry>.unmodifiable([entry]);

    final slices = reportTimeEntriesInRange(
      entries,
      start: DateTime.utc(2026, 1, 1),
      end: DateTime.utc(2026, 1, 2),
    );

    expect(slices.map((slice) => slice.durationSeconds), [3600, 24 * 3600]);
    expect(slices.map((slice) => slice.dayKey), ['2026-01-01', '2026-01-02']);
    expect(slices.first.startAt, entry.startAt);
    expect(slices.first.endAt, AppClock.date(2026, 1, 2));
    expect(slices.last.startAt, AppClock.date(2026, 1, 2));
    expect(slices.last.endAt, AppClock.date(2026, 1, 3));
    for (final slice in slices) {
      expect(identical(slice, entry), isFalse);
      final metadata = slice.toJson()
        ..remove('startAt')
        ..remove('endAt');
      final originalMetadata = Map<String, dynamic>.of(before)
        ..remove('startAt')
        ..remove('endAt');
      expect(metadata, originalMetadata);
    }
    expect(entries.single, same(entry));
    expect(entry.toJson(), before);
  });

  test(
    'copies contained entries and ignores invalid or touching intervals',
    () {
      final start = AppClock.date(2026, 1, 2);
      final end = AppClock.date(2026, 1, 3);
      final contained = TimeEntry(
        id: 'contained',
        title: 'Contained',
        startAt: AppClock.date(2026, 1, 2, 10),
        endAt: AppClock.date(2026, 1, 2, 11),
      );
      final slices = reportTimeEntriesInRange(
        [
          contained,
          TimeEntry(
            title: 'Ends at start',
            startAt: AppClock.date(2026, 1, 1, 23),
            endAt: start,
          ),
          TimeEntry(
            title: 'Starts at end',
            startAt: end,
            endAt: AppClock.date(2026, 1, 3, 1),
          ),
          TimeEntry(title: 'Zero', startAt: start, endAt: start),
          TimeEntry(title: 'Reversed', startAt: end, endAt: start),
          TimeEntry(
            title: 'No whole seconds',
            startAt: start,
            endAt: start.add(const Duration(milliseconds: 500)),
          ),
        ],
        start: DateTime(2026, 1, 2),
        end: DateTime(2026, 1, 2),
      );

      expect(slices, hasLength(1));
      expect(slices.single.toJson(), contained.toJson());
      expect(identical(slices.single, contained), isFalse);
      expect(
        reportTimeEntriesInRange(
          [contained],
          start: DateTime(2026, 1, 3),
          end: DateTime(2026, 1, 2),
        ),
        isEmpty,
      );
    },
  );

  test(
    'floating endpoints are interpreted in the application timezone',
    () async {
      final entry = TimeEntry(
        title: 'Across Shanghai midnight',
        startAt: DateTime.utc(2026, 5, 31, 15, 30),
        endAt: DateTime.utc(2026, 5, 31, 16, 30),
      );
      final date = DateTime.utc(2026, 6, 1);
      expect(
        reportTimeEntriesInRange([entry], start: date, end: date),
        isEmpty,
      );

      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      final slices = reportTimeEntriesInRange([entry], start: date, end: date);
      expect(slices.single.durationSeconds, 1800);
      expect(slices.single.startAt.toUtc(), DateTime.utc(2026, 5, 31, 16));
      expect(slices.single.dayKey, '2026-06-01');
    },
  );

  test(
    'spring DST clipping matches provider totals without persistence',
    () async {
      final entry = TimeEntry(
        id: 'spring',
        title: 'Across report boundaries and DST',
        startAt: AppClock.date(2026, 3, 7, 22).toUtc(),
        endAt: AppClock.date(2026, 3, 10, 2).toUtc(),
        category: TimeEntryCategory.work,
      );
      final prefs = await SharedPreferences.getInstance();
      final stored = [jsonEncode(entry.toJson())];
      await prefs.setStringList(TimeAuditProvider.storageKey, stored);
      final provider = TimeAuditProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      final original = provider.entries.single;
      final before = original.toJson();
      final start = DateTime.utc(2026, 3, 8);
      final end = DateTime.utc(2026, 3, 9);

      final slices = reportTimeEntriesInRange(
        provider.entries,
        start: start,
        end: end,
      );
      final report = ReportEngine.buildReport(
        start: start,
        end: end,
        todos: const [],
        habits: const [],
        sessions: const [],
        timeEntries: provider.entries,
      );
      final startInstant = AppClock.date(2026, 3, 8);
      final endExclusive = AppClock.date(2026, 3, 10);

      expect(slices.map((slice) => slice.durationSeconds), [
        23 * 3600,
        24 * 3600,
      ]);
      expect(slices.map((slice) => slice.dayKey), ['2026-03-08', '2026-03-09']);
      expect(report.timeEntrySeconds, 47 * 3600);
      expect(
        report.timeEntrySeconds,
        provider.totalSecondsInRange(startInstant, endExclusive),
      );
      expect(
        report.timeEntryByCategory[TimeEntryCategory.work],
        provider.secondsByCategory(
          startInstant,
          endExclusive,
        )[TimeEntryCategory.work],
      );
      expect({
        for (final slice in slices) slice.dayKey: slice.durationSeconds,
      }, provider.secondsByDay(startInstant, endExclusive));
      expect(provider.entries.single, same(original));
      expect(provider.entries.single.toJson(), before);
      expect(prefs.getStringList(TimeAuditProvider.storageKey), stored);
    },
  );

  test('fall DST splits at calendar midnights around a 25-hour day', () {
    final slices = reportTimeEntriesInRange(
      [
        TimeEntry(
          title: 'Fall DST',
          startAt: AppClock.date(2026, 10, 31, 23),
          endAt: AppClock.date(2026, 11, 2, 1),
        ),
      ],
      start: DateTime(2026, 10, 31),
      end: DateTime(2026, 11, 2),
    );

    expect(slices.map((slice) => slice.durationSeconds), [
      3600,
      25 * 3600,
      3600,
    ]);
    expect(slices.map((slice) => slice.dayKey), [
      '2026-10-31',
      '2026-11-01',
      '2026-11-02',
    ]);
    expect(slices[1].startAt.toUtc(), DateTime.utc(2026, 11, 1, 4));
    expect(slices[1].endAt.toUtc(), DateTime.utc(2026, 11, 2, 5));
  });
}
