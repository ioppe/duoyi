import 'dart:convert';

import '../models/todo.dart' show EisenhowerQuadrant;
import 'app_clock.dart';

/// Suggestions for a new todo; applying them remains the caller's decision.
class AiTodoBreakdown {
  const AiTodoBreakdown({
    required this.subtasks,
    this.title,
    this.listGroupName,
    this.quadrant,
    this.dateTime,
    this.hasTimeOfDay = false,
  });

  final List<String> subtasks;
  final String? title;
  final String? listGroupName;
  final EisenhowerQuadrant? quadrant;
  final DateTime? dateTime;
  final bool hasTimeOfDay;

  /// Returns null when the response has no usable string subtasks.
  /// Optional suggestions are independently validated and may be discarded.
  static AiTodoBreakdown? tryParse(
    String response, {
    required List<String> listGroups,
  }) {
    var text = response.trim();
    final fence = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(text);
    if (fence != null) text = fence[1]!;

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final rawSubtasks = decoded['subtasks'];
    if (rawSubtasks is! List) return null;
    final subtasks = <String>[];
    final seen = <String>{};
    for (final value in rawSubtasks) {
      if (value is! String) continue;
      final title = value
          .trim()
          .replaceFirst(RegExp(r'^(?:[-*•]\s*|\d+[.)、]\s*)'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty || !seen.add(title)) continue;
      subtasks.add(title);
      if (subtasks.length == 7) break;
    }
    if (subtasks.isEmpty) return null;

    final group = decoded['list_group'];
    final parsedDate = _parseDateTime(decoded['date_time']);
    final rawTitle = decoded['title'];
    final title = rawTitle is String
        ? rawTitle.trim().replaceAll(RegExp(r'\s+'), ' ')
        : null;
    return AiTodoBreakdown(
      subtasks: List.unmodifiable(subtasks),
      title: title != null && title.isNotEmpty && title.runes.length <= 80
          ? title
          : null,
      listGroupName: group is String && listGroups.contains(group)
          ? group
          : null,
      quadrant: switch (decoded['quadrant']) {
        'Q1' => EisenhowerQuadrant.urgentImportant,
        'Q2' => EisenhowerQuadrant.notUrgentImportant,
        'Q3' => EisenhowerQuadrant.urgentNotImportant,
        'Q4' => EisenhowerQuadrant.notUrgentNotImportant,
        _ => null,
      },
      dateTime: parsedDate?.value,
      hasTimeOfDay:
          parsedDate != null &&
          parsedDate.hasTime &&
          decoded['has_time'] == true,
    );
  }

  static ({DateTime value, bool hasTime})? _parseDateTime(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})'
      r'(?:[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?'
      r'(Z|[+-]\d{2}:?\d{2})?)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final hour = int.parse(match[4] ?? '0');
    final minute = int.parse(match[5] ?? '0');
    final second = int.parse(match[6] ?? '0');
    if (year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    if (match[4] == null) {
      return (value: DateTime(year, month, day), hasTime: false);
    }
    final zone = match[8];
    if (zone != null) {
      if (zone.toUpperCase() != 'Z') {
        final offset = zone.substring(1).replaceAll(':', '');
        if (int.parse(offset.substring(0, 2)) > 23 ||
            int.parse(offset.substring(2)) > 59) {
          return null;
        }
      }
      final instant = DateTime.tryParse(text);
      if (instant == null) return null;
      return (value: AppClock.toLocal(instant), hasTime: true);
    }
    final fractional = int.parse((match[7] ?? '').padRight(6, '0'));
    final value = AppClock.date(
      year,
      month,
      day,
      hour,
      minute,
      second,
      fractional ~/ 1000,
      fractional % 1000,
    );
    // Reject wall times normalized across a daylight-saving gap as well.
    if (value.year != year ||
        value.month != month ||
        value.day != day ||
        value.hour != hour ||
        value.minute != minute ||
        value.second != second) {
      return null;
    }
    return (value: value, hasTime: match[4] != null);
  }
}
