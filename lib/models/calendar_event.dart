import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/app_clock.dart';

import '../core/i18n.dart';

enum CalendarEventType {
  event,
  todo,
  habit,
  pomodoro,
  anniversary,
  course,
  diary,
  countdown,
  goal,
  timeEntry,
}

extension CalendarEventTypeX on CalendarEventType {
  /// Retired values remain parseable for backups and synchronization.
  bool get isVisible => this != CalendarEventType.diary;

  String get label => switch (this) {
    CalendarEventType.event => I18n.tr('calendar_event.event'),
    CalendarEventType.todo => I18n.tr('calendar_event.todo'),
    CalendarEventType.habit => I18n.tr('calendar_event.habit'),
    CalendarEventType.pomodoro => I18n.tr('calendar_event.pomodoro'),
    CalendarEventType.anniversary => I18n.tr('calendar_event.anniversary'),
    CalendarEventType.course => I18n.tr('calendar_event.course'),
    CalendarEventType.diary => I18n.tr('feature.unavailable'),
    CalendarEventType.countdown => I18n.tr('calendar_event.countdown'),
    CalendarEventType.goal => I18n.tr('calendar_event.goal'),
    CalendarEventType.timeEntry => I18n.tr('calendar_event.time_entry'),
  };
}

class CalendarEvent {
  final String id;
  final String title;
  final DateTime date;
  final DateTime? endDate;
  final CalendarEventType type;
  final Color color;
  final bool isCompleted;
  final String? sourceId;
  final String? subtitle;
  final String? projectId;
  final String? projectName;
  final String? workspaceId;
  final TimeOfDay? time;
  final bool hasConflict;
  final int conflictCount;
  final String? note;
  final DateTime? updatedAt;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.type,
    required this.color,
    this.isCompleted = false,
    this.sourceId,
    this.subtitle,
    this.projectId,
    this.projectName,
    this.workspaceId,
    this.time,
    this.endDate,
    this.hasConflict = false,
    this.conflictCount = 0,
    this.note,
    this.updatedAt,
  });

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool get canOpen =>
      type.isVisible && sourceId != null && sourceId!.isNotEmpty;

  String? get projectKey {
    if (projectId != null && projectId!.isNotEmpty) return projectId;
    if (projectName != null && projectName!.isNotEmpty) return projectName;
    return null;
  }

  /// Timed instants follow the application zone; all-day dates stay floating.
  CalendarEvent inAppTimeZone() {
    if (type != CalendarEventType.event &&
        type != CalendarEventType.pomodoro &&
        type != CalendarEventType.timeEntry) {
      return this;
    }
    if (time == null && type == CalendarEventType.event) return this;
    final instant =
        type == CalendarEventType.pomodoro ||
        type == CalendarEventType.timeEntry;
    final local = instant || date.isUtc || date is tz.TZDateTime
        ? AppClock.toLocal(date)
        : AppClock.date(
            date.year,
            date.month,
            date.day,
            time!.hour,
            time!.minute,
          );
    final end = endDate;
    return copyWith(
      date: local,
      endDate: end == null
          ? null
          : instant
          ? AppClock.toLocal(end)
          : _appWallTime(end),
      time: TimeOfDay.fromDateTime(local),
    );
  }

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? date,
    DateTime? endDate,
    CalendarEventType? type,
    Color? color,
    bool? isCompleted,
    String? sourceId,
    String? subtitle,
    String? projectId,
    String? projectName,
    String? workspaceId,
    TimeOfDay? time,
    bool? hasConflict,
    int? conflictCount,
    String? note,
    DateTime? updatedAt,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      endDate: endDate ?? this.endDate,
      type: type ?? this.type,
      color: color ?? this.color,
      isCompleted: isCompleted ?? this.isCompleted,
      sourceId: sourceId ?? this.sourceId,
      subtitle: subtitle ?? this.subtitle,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      workspaceId: workspaceId ?? this.workspaceId,
      time: time ?? this.time,
      hasConflict: hasConflict ?? this.hasConflict,
      conflictCount: conflictCount ?? this.conflictCount,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': time == null
        ? date.toIso8601String()
        : inAppTimeZone().date.toUtc().toIso8601String(),
    'endDate': time == null
        ? endDate?.toIso8601String()
        : endDate == null
        ? null
        : _appWallTime(endDate!).toUtc().toIso8601String(),
    'type': type.name,
    'color': color.toARGB32(),
    'isCompleted': isCompleted,
    'sourceId': sourceId,
    'subtitle': subtitle,
    'projectId': projectId,
    'projectName': projectName,
    'workspaceId': workspaceId,
    'time': time == null ? null : '${time!.hour}:${time!.minute}',
    'hasConflict': hasConflict,
    'conflictCount': conflictCount,
    'note': note,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final parsedType = CalendarEventType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => CalendarEventType.event,
    );
    final timeRaw = json['time']?.toString();
    final timeParts = timeRaw?.split(':');
    TimeOfDay? parsedTime;
    if (timeParts != null && timeParts.length == 2) {
      final hour = int.tryParse(timeParts[0]);
      final minute = int.tryParse(timeParts[1]);
      if (hour != null && minute != null) {
        parsedTime = TimeOfDay(hour: hour, minute: minute);
      }
    }
    final rawColor = json['color'];
    return CalendarEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      date: DateTime.parse(json['date'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
      type: parsedType,
      color: Color(rawColor is int ? rawColor : 0xFF5B6EE1),
      isCompleted: json['isCompleted'] == true,
      sourceId: json['sourceId']?.toString(),
      subtitle: json['subtitle']?.toString(),
      projectId: json['projectId']?.toString(),
      projectName: json['projectName']?.toString(),
      workspaceId: json['workspaceId']?.toString(),
      time: parsedTime,
      hasConflict: json['hasConflict'] == true,
      conflictCount: (json['conflictCount'] as num?)?.toInt() ?? 0,
      note: json['note']?.toString(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

DateTime _appWallTime(DateTime value) {
  if (value.isUtc || value is tz.TZDateTime) return AppClock.toLocal(value);
  return AppClock.date(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}
