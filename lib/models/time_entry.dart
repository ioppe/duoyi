import 'package:uuid/uuid.dart';

import '../core/app_clock.dart';
import '../core/i18n.dart';

const _timeEntryUuid = Uuid();
const Object _unsetTimeEntry = Object();

enum TimeEntrySource { manual, pomodoro, todo, habit, goal }

enum TimeEntryCategory { focus, todo, habit, goal, study, work, life, other }

extension TimeEntrySourceX on TimeEntrySource {
  String get label => switch (this) {
    TimeEntrySource.manual => I18n.tr('time_entry.source.manual'),
    TimeEntrySource.pomodoro => I18n.tr('time_entry.source.pomodoro'),
    TimeEntrySource.todo => I18n.tr('time_entry.source.todo'),
    TimeEntrySource.habit => I18n.tr('time_entry.source.habit'),
    TimeEntrySource.goal => I18n.tr('time_entry.source.goal'),
  };
}

extension TimeEntryCategoryX on TimeEntryCategory {
  String get label => switch (this) {
    TimeEntryCategory.focus => I18n.tr('time_entry.category.focus'),
    TimeEntryCategory.todo => I18n.tr('time_entry.category.todo'),
    TimeEntryCategory.habit => I18n.tr('time_entry.category.habit'),
    TimeEntryCategory.goal => I18n.tr('time_entry.category.goal'),
    TimeEntryCategory.study => I18n.tr('time_entry.category.study'),
    TimeEntryCategory.work => I18n.tr('time_entry.category.work'),
    TimeEntryCategory.life => I18n.tr('time_entry.category.life'),
    TimeEntryCategory.other => I18n.tr('time_entry.category.other'),
  };
}

class TimeEntry {
  final String id;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final TimeEntryCategory category;
  final TimeEntrySource source;
  final String? sourceId;
  final String? dedupeKey;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  TimeEntry({
    String? id,
    required this.title,
    required this.startAt,
    required this.endAt,
    this.category = TimeEntryCategory.other,
    this.source = TimeEntrySource.manual,
    this.sourceId,
    this.dedupeKey,
    this.note = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _timeEntryUuid.v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  int get durationSeconds {
    final seconds = endAt.difference(startAt).inSeconds;
    return seconds <= 0 ? 0 : seconds;
  }

  String get dayKey {
    final day = AppClock.toLocal(startAt);
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  }

  bool overlaps(DateTime start, DateTime end) {
    return startAt.isBefore(end) && endAt.isAfter(start);
  }

  TimeEntry copyWith({
    String? title,
    DateTime? startAt,
    DateTime? endAt,
    TimeEntryCategory? category,
    TimeEntrySource? source,
    Object? sourceId = _unsetTimeEntry,
    Object? dedupeKey = _unsetTimeEntry,
    String? note,
  }) {
    return TimeEntry(
      id: id,
      title: title ?? this.title,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      category: category ?? this.category,
      source: source ?? this.source,
      sourceId: identical(sourceId, _unsetTimeEntry)
          ? this.sourceId
          : sourceId as String?,
      dedupeKey: identical(dedupeKey, _unsetTimeEntry)
          ? this.dedupeKey
          : dedupeKey as String?,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'category': category.index,
    'source': source.index,
    'sourceId': sourceId,
    'dedupeKey': dedupeKey,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TimeEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final start = DateTime.tryParse(json['startAt']?.toString() ?? '') ?? now;
    final end = DateTime.tryParse(json['endAt']?.toString() ?? '') ?? start;
    return TimeEntry(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '时间记录',
      startAt: start,
      endAt: end,
      category:
          _enumFromJson(TimeEntryCategory.values, json['category']) ??
          TimeEntryCategory.other,
      source:
          _enumFromJson(TimeEntrySource.values, json['source']) ??
          TimeEntrySource.manual,
      sourceId: json['sourceId']?.toString(),
      dedupeKey: json['dedupeKey']?.toString(),
      note: json['note']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
    );
  }
}

T? _enumFromJson<T extends Enum>(List<T> values, Object? raw) {
  final int? index = raw is num ? raw.toInt() : null;
  if (index != null) {
    if (index < 0 || index >= values.length) return null;
    return values[index];
  }
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
  }
  return null;
}
