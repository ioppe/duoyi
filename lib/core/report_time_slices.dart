import '../models/time_entry.dart';
import 'app_clock.dart';

/// Clips time entries to inclusive floating calendar dates in the app zone.
///
/// Entries crossing application midnights become separate daily slices. These
/// copies retain the original identity and metadata and are only for reporting;
/// they must not be persisted as additional time entries.
List<TimeEntry> reportTimeEntriesInRange(
  Iterable<TimeEntry> entries, {
  required DateTime start,
  required DateTime end,
}) {
  final startInstant = AppClock.date(start.year, start.month, start.day);
  final endExclusive = AppClock.date(end.year, end.month, end.day + 1);
  if (!startInstant.isBefore(endExclusive)) return const [];

  final slices = <TimeEntry>[];
  for (final entry in entries) {
    if (entry.durationSeconds <= 0 ||
        !entry.overlaps(startInstant, endExclusive)) {
      continue;
    }
    var cursor = entry.startAt.isBefore(startInstant)
        ? startInstant
        : entry.startAt;
    final clippedEnd = entry.endAt.isAfter(endExclusive)
        ? endExclusive
        : entry.endAt;
    while (cursor.isBefore(clippedEnd)) {
      final day = AppClock.toLocal(cursor);
      final midnight = AppClock.date(day.year, day.month, day.day + 1);
      final sliceEnd = midnight.isBefore(clippedEnd) ? midnight : clippedEnd;
      if (sliceEnd.difference(cursor).inSeconds > 0) {
        slices.add(
          TimeEntry(
            id: entry.id,
            title: entry.title,
            startAt: cursor,
            endAt: sliceEnd,
            category: entry.category,
            source: entry.source,
            sourceId: entry.sourceId,
            dedupeKey: entry.dedupeKey,
            note: entry.note,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
          ),
        );
      }
      cursor = sliceEnd;
    }
  }
  return slices;
}
